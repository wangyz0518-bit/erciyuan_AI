#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ConversationVADState ConversationVADState;
ConversationVADState *conversation_vad_open(const char *model_path);
void conversation_vad_reset(ConversationVADState *state);
int conversation_vad_score(ConversationVADState *state, const uint8_t *pcm,
                           size_t size, float *score);
void conversation_vad_close(ConversationVADState *state);

#ifdef __cplusplus
}
#endif
