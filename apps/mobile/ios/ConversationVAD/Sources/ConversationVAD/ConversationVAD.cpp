#include "ConversationVAD.h"
#if __has_include(<onnxruntime/onnxruntime_cxx_api.h>)
#include <onnxruntime/onnxruntime_cxx_api.h>
#else
#include <onnxruntime_cxx_api.h>
#endif
#include <algorithm>
#include <array>
#include <cmath>
#include <stdexcept>

struct ConversationVADState {
    Ort::Env env{ORT_LOGGING_LEVEL_WARNING, "speech"};
    Ort::SessionOptions options;
    Ort::Session session{nullptr};
    Ort::MemoryInfo memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    std::array<float, 576> window{};
    std::array<float, 256> hidden{};

    explicit ConversationVADState(const char *path) {
        options.SetIntraOpNumThreads(1);
        session = Ort::Session(env, path, options);
    }

    float infer(const uint8_t *pcm) {
        for (size_t i = 0; i < 512; ++i) {
            int value = pcm[i * 2] | (pcm[i * 2 + 1] << 8);
            window[64 + i] = (value >= 32768 ? value - 65536 : value) / 32768.0f;
        }
        const int64_t audioShape[]{1, 576}, stateShape[]{2, 1, 128};
        int64_t rate = 16000;
        std::array<Ort::Value, 3> tensors{
            Ort::Value::CreateTensor<float>(memory, window.data(), window.size(), audioShape, 2),
            Ort::Value::CreateTensor<float>(memory, hidden.data(), hidden.size(), stateShape, 3),
            Ort::Value::CreateTensor<int64_t>(memory, &rate, 1, nullptr, 0)
        };
        const char *inputs[]{"input", "state", "sr"};
        const char *outputs[]{"output", "stateN"};
        auto result = session.Run(Ort::RunOptions{nullptr}, inputs, tensors.data(), tensors.size(), outputs, 2);
        if (result[0].GetTensorTypeAndShapeInfo().GetElementCount() != 1 ||
            result[1].GetTensorTypeAndShapeInfo().GetElementCount() != hidden.size())
            throw std::runtime_error("Unexpected VAD output");
        std::copy_n(result[1].GetTensorData<float>(), hidden.size(), hidden.begin());
        std::copy_n(window.begin() + 512, 64, window.begin());
        return result[0].GetTensorData<float>()[0];
    }
};

ConversationVADState *conversation_vad_open(const char *path) {
    if (!path) return nullptr;
    try { return new ConversationVADState(path); }
    catch (...) { return nullptr; }
}

void conversation_vad_reset(ConversationVADState *s) {
    if (s) {
        s->window.fill(0);
        s->hidden.fill(0);
    }
}

int conversation_vad_score(ConversationVADState *s, const uint8_t *pcm, size_t size, float *score) {
    if (!s || !pcm || size != 1024 || !score) return 0;
    try {
        *score = s->infer(pcm);
        return std::isfinite(*score) && *score >= 0 && *score <= 1;
    } catch (...) { return 0; }
}

void conversation_vad_close(ConversationVADState *s) { delete s; }
