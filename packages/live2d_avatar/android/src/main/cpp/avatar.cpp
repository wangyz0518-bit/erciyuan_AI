#include <jni.h>
#include <android/asset_manager_jni.h>
#include <android/native_window_jni.h>
#include <android/log.h>
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <CubismFramework.hpp>
#include <ICubismAllocator.hpp>
#include <CubismModelSettingJson.hpp>
#include <Model/CubismUserModel.hpp>
#include <Model/CubismModel.hpp>
#include <Model/CubismMoc.hpp>
#include <Math/CubismModelMatrix.hpp>
#include <Motion/CubismMotion.hpp>
#include <Motion/CubismMotionManager.hpp>
#include <Motion/CubismExpressionMotionManager.hpp>
#include <Effect/CubismEyeBlink.hpp>
#include <Physics/CubismPhysics.hpp>
#include <Effect/CubismPose.hpp>
#include <Id/CubismIdManager.hpp>
#include <Rendering/OpenGL/CubismRenderer_OpenGLES2.hpp>
#include <Rendering/OpenGL/CubismOffscreenManager_OpenGLES2.hpp>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
#include <fstream>
#include <set>
#include <limits>
#define STB_IMAGE_IMPLEMENTATION
#include <stb_image.h>

using namespace Live2D::Cubism::Framework;
namespace {
// A single model/view per Flutter engine is deliberately supported in this PoC.
// All Core, Framework and GL calls run on the plugin's one render thread.
AAssetManager* assets = nullptr;
class Allocator final : public ICubismAllocator {
 void* Allocate(csmSizeType n) override { return malloc(n); }
 void Deallocate(void* p) override { free(p); }
 void* AllocateAligned(csmSizeType n, csmUint32 a) override {
   void* p=nullptr; return posix_memalign(&p, std::max<size_t>(a,sizeof(void*)), n)==0?p:nullptr;
 }
 void DeallocateAligned(void* p) override { free(p); }
} allocator;
std::vector<unsigned char> read(const std::string& path) {
 AAsset* f=AAssetManager_open(assets,path.c_str(),AASSET_MODE_BUFFER);
 if(!f) throw std::runtime_error("Missing asset: "+path);
 const auto n=AAsset_getLength(f);
 if(n<=0 || n>64*1024*1024) { AAsset_close(f); throw std::runtime_error("Invalid asset size"); }
 std::vector<unsigned char> data(n);
 const auto got=AAsset_read(f,data.data(),n); AAsset_close(f);
 if(got!=n) throw std::runtime_error("Incomplete asset: "+path);
 return data;
}
csmByte* shaderFile(const std::string name,csmSizeInt* size) {
 try { auto b=read("live2d_shaders/"+name); *size=b.size();
   auto p=new csmByte[b.size()]; std::copy(b.begin(),b.end(),p); return p;
 } catch(...) { *size=0; return nullptr; }
}
void releaseFile(csmByte* p) { delete[] p; }
void log(const char* s) { __android_log_print(ANDROID_LOG_INFO,"Live2D","%s",s); }
std::string str(JNIEnv* e,jstring s) {
 const char* p=e->GetStringUTFChars(s,nullptr); std::string r(p); e->ReleaseStringUTFChars(s,p); return r;
}
void error(JNIEnv* e,const std::exception& x) {
 e->ThrowNew(e->FindClass("java/lang/IllegalStateException"),x.what());
}
class Model final : public CubismUserModel {
 std::unique_ptr<CubismModelSettingJson> settings;
 std::map<std::string,ACubismMotion*> motions,expressions;
 std::vector<GLuint> textures;
 std::string idle;
 bool manualPose = false;
 bool packageMode = false;
 std::string playing;
 CubismMotionQueueEntryHandle playingHandle = InvalidMotionQueueEntryHandleValue;
 std::vector<float> partDefaults;
 std::vector<CubismIdHandle> opacityIds;
 float centerX=0,centerY=0,boundsWidth=1,boundsHeight=1;
 public:
 ~Model() override {
   _motionManager->StopAllMotions(); _expressionManager->StopAllMotions();
   for(auto& p:motions) ACubismMotion::Delete(p.second);
   for(auto& p:expressions) ACubismMotion::Delete(p.second);
   DeleteRenderer();
   if(!textures.empty()) glDeleteTextures(textures.size(),textures.data());
 }
 void load(const std::string& path,int w,int h,const std::string& root="",
           const std::vector<std::string>& requiredParameters={},const std::vector<std::string>& requiredParts={},
           const std::map<std::string,std::string>& normalizedJson={},const std::vector<std::string>& opacityParts={}) {
   packageMode=!root.empty();
   auto read=[&](const std::string& name) {
     if(!packageMode) return ::read(name);
     char* resolved=realpath(name.c_str(),nullptr);
     if(!resolved) throw std::runtime_error("Package resource missing");
     std::string canonical(resolved); free(resolved);
     if(canonical.rfind(root+"/",0)!=0) throw std::runtime_error("Package path escapes root");
     auto normalized=normalizedJson.find(canonical);
     if(normalized!=normalizedJson.end()) return std::vector<unsigned char>(normalized->second.begin(),normalized->second.end());
     std::ifstream f(canonical,std::ios::binary|std::ios::ate);
     auto n=f.tellg();
     if(n<=0 || n>64*1024*1024) throw std::runtime_error("Package file size invalid");
     std::vector<unsigned char> b(static_cast<size_t>(n)); f.seekg(0);
     if(!f.read(reinterpret_cast<char*>(b.data()),n)) throw std::runtime_error("Package read incomplete");
     return b;
   };
   auto json=read(path); settings=std::make_unique<CubismModelSettingJson>(json.data(),json.size());
   std::string dir=path.substr(0,path.find_last_of('/')+1);
   auto moc=read(dir+settings->GetModelFileName());
   auto version=CubismMoc::GetMocVersionFromBuffer(moc.data(),moc.size());
   if(!version || version>CubismMoc::GetLatestMocVersion()) throw std::runtime_error("MOC3 version unsupported");
   LoadModel(moc.data(),moc.size(),true);
   if(!_model) throw std::runtime_error("MOC3 consistency check failed");
   std::set<std::string> realParameters,realParts;
   for(int i=0;i<_model->GetParameterCount();i++) realParameters.insert(_model->GetParameterId(i)->GetString().GetRawString());
   for(int i=0;i<_model->GetPartCount();i++) {
     realParts.insert(_model->GetPartId(i)->GetString().GetRawString());
     partDefaults.push_back(_model->GetPartOpacity(i));
   }
   for(const auto& id:requiredParameters) if(!realParameters.count(id)) throw std::runtime_error("Unknown MOC parameter: "+id);
   for(const auto& id:requiredParts) if(!realParts.count(id)) throw std::runtime_error("Unknown MOC part: "+id);
   for(const auto& name:opacityParts) {
     auto id=CubismFramework::GetIdManager()->GetId(name.c_str());opacityIds.push_back(id);
     _model->SetParameterValue(id,_model->GetPartOpacity(_model->GetPartIndex(id)));
   }
   auto optional=[&](const char* file,auto fn) { if(file && *file) {auto b=read(dir+file);fn(b);} };
   optional(settings->GetPhysicsFileName(),[&](auto& b){LoadPhysics(b.data(),b.size());});
   optional(settings->GetPoseFileName(),[&](auto& b){LoadPose(b.data(),b.size());});
   if (_pose) _pose->UpdateParameters(_model, 0);
   _eyeBlink=CubismEyeBlink::Create(settings.get());
   for(int i=0;i<settings->GetExpressionCount();++i) {
     auto b=read(dir+settings->GetExpressionFileName(i));
     auto p=LoadExpression(b.data(),b.size(),settings->GetExpressionName(i));
     if(!p) throw std::runtime_error("Invalid expression");
     expressions.emplace(settings->GetExpressionName(i),p);
   }
   csmVector<CubismIdHandle> eyes,lips;
   for(int i=0;i<settings->GetEyeBlinkParameterCount();++i) eyes.PushBack(settings->GetEyeBlinkParameterId(i));
   for(int i=0;i<settings->GetLipSyncParameterCount();++i) lips.PushBack(settings->GetLipSyncParameterId(i));
   for(int g=0;g<settings->GetMotionGroupCount();++g) {
     auto group=settings->GetMotionGroupName(g);
     for(int i=0;i<settings->GetMotionCount(group);++i) {
       auto b=read(dir+settings->GetMotionFileName(group,i));
       std::string key=std::string(group)+":"+std::to_string(i);
       auto p=static_cast<CubismMotion*>(LoadMotion(b.data(),b.size(),key.c_str(),nullptr,nullptr,settings.get(),group,i,true));
       if(!p) throw std::runtime_error("Invalid motion");
       p->SetEffectIds(eyes,lips); motions.emplace(key,p);
       if(std::string(group)=="Idle" && idle.empty()) idle=key;
     }
   }
   csmMap<csmString,csmFloat32> layout; settings->GetLayoutMap(layout); _modelMatrix->SetupFromLayout(layout);
   _model->SaveParameters(); CreateRenderer(w,h);
   for(int i=0;i<settings->GetTextureCount();++i) {
     auto b=read(dir+settings->GetTextureFileName(i)); int tw,th,ch;
     if(!stbi_info_from_memory(b.data(),b.size(),&tw,&th,&ch) || tw<=0 || th<=0 ||
         (packageMode && (tw>2048 || th>2048))) throw std::runtime_error("Invalid texture dimensions");
     auto pixels=stbi_load_from_memory(b.data(),b.size(),&tw,&th,&ch,4);
     if(!pixels) throw std::runtime_error("Invalid texture");
     GLuint t; glGenTextures(1,&t); textures.push_back(t); glBindTexture(GL_TEXTURE_2D,t);
     glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR); glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
     glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE); glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
     glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA,tw,th,0,GL_RGBA,GL_UNSIGNED_BYTE,pixels); stbi_image_free(pixels);
     // Cubism R5 selects GL_LINEAR_MIPMAP_LINEAR for each drawable.
     glGenerateMipmap(GL_TEXTURE_2D);
     GetRenderer<Rendering::CubismRenderer_OpenGLES2>()->BindTexture(i,t);
   }
   GetRenderer<Rendering::CubismRenderer_OpenGLES2>()->IsPremultipliedAlpha(false);
   if(packageMode) {
     _model->Update();
     float left=std::numeric_limits<float>::max(),bottom=left,right=-left,top=-left;
     for(int d=0;d<_model->GetDrawableCount();d++) {
       if(_model->GetDrawableOpacity(d)<=0) continue;
       const float* vertices=_model->GetDrawableVertices(d);
       for(int v=0;v<_model->GetDrawableVertexCount(d);v++) {
         left=std::min(left,vertices[2*v]);right=std::max(right,vertices[2*v]);
         bottom=std::min(bottom,vertices[2*v+1]);top=std::max(top,vertices[2*v+1]);
       }
     }
     if(!(right>left && top>bottom)) throw std::runtime_error("Model has no visible geometry");
     centerX=(left+right)/2;centerY=(bottom+top)/2;boundsWidth=right-left;boundsHeight=top-bottom;
   }
 }
 void expression(const std::string& id) {
   auto it=expressions.find(id); if(it==expressions.end()) throw std::runtime_error("Unsupported expression: "+id);
   resumeAutomaticPose();
   _expressionManager->StartMotion(it->second,false);
 }
 void motion(const std::string& id) {
   auto it=motions.find(id); if(it==motions.end()) throw std::runtime_error("Unsupported motion: "+id);
   if(packageMode && !playing.empty()) throw std::runtime_error("busy: action is already playing");
   resumeAutomaticPose();
   playingHandle=_motionManager->StartMotionPriority(it->second,false,3);
   playing=id;
 }
 std::string action() const { return playing; }
 void reset() {
   manualPose=true; resumeAutomaticPose(); playing.clear();
   for(int i=0;i<_model->GetPartCount();i++) _model->SetPartOpacity(i,partDefaults[i]);
   for(auto id:opacityIds) _model->SetParameterValue(id,partDefaults[_model->GetPartIndex(id)]);
   _model->SetModelOpacity(1.f);
   if(_pose) _pose->Reset(_model);
 }
 CubismModel& parameters() { return *_model; }

 void setPose(const std::vector<float>& updates) {
   if (updates.size() != static_cast<size_t>(_model->GetParameterCount())) {
     throw std::runtime_error("Pose does not match the model parameters");
   }
   manualPose = true;
   for (int i = 0; i < _model->GetParameterCount(); ++i) {
     if (std::isfinite(updates[i])) {
       _model->SetParameterValue(i, updates[i]);
     }
   }
 }

 void resumeAutomaticPose() {
   if (!manualPose) return;
   manualPose = false;
   _motionManager->StopAllMotions();
   _expressionManager->StopAllMotions();
   if (_pose) _pose->Reset(_model);
   for (int i = 0; i < _model->GetParameterCount(); ++i) {
     _model->SetParameterValue(i, _model->GetParameterDefaultValue(i));
   }
   _model->SaveParameters();
 }

 void updateAutomatic(float dt, float mouth) {
   _model->LoadParameters();
   if(!playing.empty() && _motionManager->IsFinished(playingHandle)) playing.clear();
   if (_motionManager->IsFinished() && !idle.empty()) {
     _motionManager->StartMotionPriority(motions.at(idle), false, 1);
   }
   const bool moved = _motionManager->UpdateMotion(_model, dt);
   _model->SaveParameters();
   if(!playing.empty() && _motionManager->IsFinished(playingHandle)) playing.clear();
   if (!moved && _eyeBlink) _eyeBlink->UpdateParameters(_model, dt);
   _expressionManager->UpdateMotion(_model, dt);
   if (_physics) _physics->Evaluate(_model, dt);
   for (int i = 0; i < settings->GetLipSyncParameterCount(); ++i) {
     _model->SetParameterValue(settings->GetLipSyncParameterId(i), mouth);
   }
 }

 void draw(float dt,int w,int h,float mouth,float zoom,float x,float y) {
   if (!manualPose) updateAutomatic(dt, mouth);
   // Cubism pose drives part visibility (e.g. which Haru arm is drawn).
   if(_pose) _pose->UpdateParameters(_model,dt);
   // R5 writes PartOpacity curves into virtual parameter IDs; apply these to real parts.
   for(auto id:opacityIds) _model->SetPartOpacity(id,_model->GetParameterValue(id));
   _model->Update();
   CubismMatrix44 m;
   if(packageMode) {
     // Fit visible rest geometry once, leaving room for authored movements; no camera pumping.
     float sy=std::min(1.65f/boundsHeight,1.65f*float(w)/h/boundsWidth),sx=sy*float(h)/w;
     m.Scale(sx,sy);m.Translate(-centerX*sx,-centerY*sy);
   } else {
     _modelMatrix->SetHeight(2.0f);
     m.Translate(x,y);m.Scale(zoom*float(h)/w,zoom);m.MultiplyByMatrix(_modelMatrix);
   }
   GetRenderer<Rendering::CubismRenderer_OpenGLES2>()->SetMvpMatrix(&m);
   GetRenderer<Rendering::CubismRenderer_OpenGLES2>()->DrawModel();
 }
};
struct Session {
 CubismFramework::Option option;
 EGLDisplay display=EGL_NO_DISPLAY; EGLContext context=EGL_NO_CONTEXT; EGLSurface surface=EGL_NO_SURFACE;
 ANativeWindow* window=nullptr; std::unique_ptr<Model> model;
 int w=720,h=1280; float mouth=0,zoom=1,x=0,y=0; bool started=false;
 std::chrono::steady_clock::time_point previous=std::chrono::steady_clock::now();
 ~Session() {
   if(display!=EGL_NO_DISPLAY && context!=EGL_NO_CONTEXT) {
     eglMakeCurrent(display,surface,surface,context); model.reset();
     if(started) {
       Rendering::CubismOffscreenManager_OpenGLES2::ReleaseInstance();
       CubismFramework::Dispose(); CubismFramework::CleanUp();
     }
     eglMakeCurrent(display,EGL_NO_SURFACE,EGL_NO_SURFACE,EGL_NO_CONTEXT);
     if(surface!=EGL_NO_SURFACE) eglDestroySurface(display,surface);
     eglDestroyContext(display,context); eglTerminate(display);
   }
   if(window) ANativeWindow_release(window);
 }
 void init(JNIEnv* e,jobject output) {
   window=ANativeWindow_fromSurface(e,output); if(!window) throw std::runtime_error("Invalid surface");
   display=eglGetDisplay(EGL_DEFAULT_DISPLAY);
   if(!eglInitialize(display,nullptr,nullptr)) throw std::runtime_error("eglInitialize failed");
   const EGLint attrs[]={EGL_SURFACE_TYPE,EGL_WINDOW_BIT,EGL_RENDERABLE_TYPE,EGL_OPENGL_ES2_BIT,EGL_RED_SIZE,8,EGL_GREEN_SIZE,8,EGL_BLUE_SIZE,8,EGL_ALPHA_SIZE,8,EGL_NONE};
   EGLConfig config; EGLint count;
   if(!eglChooseConfig(display,attrs,&config,1,&count)||!count) throw std::runtime_error("RGBA EGL config unavailable");
   const EGLint ctx[]={EGL_CONTEXT_CLIENT_VERSION,2,EGL_NONE}; context=eglCreateContext(display,config,EGL_NO_CONTEXT,ctx);
   surface=eglCreateWindowSurface(display,config,window,nullptr);
   if(context==EGL_NO_CONTEXT||surface==EGL_NO_SURFACE||!eglMakeCurrent(display,surface,surface,context)) throw std::runtime_error("EGL surface initialization failed");
   eglSwapInterval(display,1);
   option.LogFunction=log; option.LoggingLevel=CubismFramework::Option::LogLevel_Warning;
   option.LoadFileFunction=shaderFile; option.ReleaseBytesFunction=releaseFile;
   CubismFramework::StartUp(&allocator,&option); CubismFramework::Initialize(); started=true;
 }
 void frame() {
   eglQuerySurface(display,surface,EGL_WIDTH,&w); eglQuerySurface(display,surface,EGL_HEIGHT,&h);
   glBindFramebuffer(GL_FRAMEBUFFER,0); glViewport(0,0,w,h); glClearColor(0,0,0,0); glClear(GL_COLOR_BUFFER_BIT);
   auto now=std::chrono::steady_clock::now(); float dt=std::chrono::duration<float>(now-previous).count(); previous=now;
   auto offscreen=Rendering::CubismOffscreenManager_OpenGLES2::GetInstance();
   offscreen->BeginFrameProcess();
   if(model) model->draw(std::min(dt,.05f),w,h,mouth,zoom,x,y);
   offscreen->EndFrameProcess();offscreen->ReleaseStaleRenderTextures();
   if(!eglSwapBuffers(display,surface)) throw std::runtime_error("EGL swap failed");
 }
};
}
#define JNI_METHOD(name) Java_dev_erciyuan_live2d_Live2dPlugin_##name
extern "C" JNIEXPORT jlong JNICALL JNI_METHOD(nativeCreate)(JNIEnv* e,jclass,jobject manager,jobject surface) {
 try { assets=AAssetManager_fromJava(e,manager); auto s=std::make_unique<Session>(); s->init(e,surface);return reinterpret_cast<jlong>(s.release()); }
 catch(const std::exception& x){error(e,x);return 0;}
}
extern "C" JNIEXPORT void JNICALL JNI_METHOD(nativeLoad)(JNIEnv* e,jclass,jlong handle,jstring path) {
 try { auto s=reinterpret_cast<Session*>(handle); auto m=std::make_unique<Model>();m->load(str(e,path),s->w,s->h);s->model=std::move(m); }
 catch(const std::exception& x){error(e,x);}
}
extern "C" JNIEXPORT void JNICALL JNI_METHOD(nativeLoadPackage)(JNIEnv* e,jclass,jlong handle,jstring root,jstring path,jobjectArray parameters,jobjectArray parts,jobjectArray opacityParts,jobjectArray paths,jobjectArray json) {
 try {
   auto strings=[&](jobjectArray a) { std::vector<std::string> result;
     for(int i=0;i<e->GetArrayLength(a);i++) {auto s=static_cast<jstring>(e->GetObjectArrayElement(a,i));result.push_back(str(e,s));e->DeleteLocalRef(s);} return result; };
   auto s=reinterpret_cast<Session*>(handle); auto m=std::make_unique<Model>();
   auto names=strings(paths),data=strings(json); std::map<std::string,std::string> normalized;
   for(size_t i=0;i<names.size();i++) normalized.emplace(str(e,root)+"/"+names[i],data.at(i));
   m->load(str(e,path),s->w,s->h,str(e,root),strings(parameters),strings(parts),normalized,strings(opacityParts));
   s->model=std::move(m); s->zoom=1; s->x=0; s->y=0; s->mouth=0;
   s->previous=std::chrono::steady_clock::now();
 } catch(const std::exception& x){error(e,x);}
}
extern "C" JNIEXPORT jstring JNICALL JNI_METHOD(nativeAction)(JNIEnv* e,jclass,jlong h) {
 auto& m=reinterpret_cast<Session*>(h)->model;
 return e->NewStringUTF(m?m->action().c_str():"");
}
extern "C" JNIEXPORT void JNICALL JNI_METHOD(nativeCommand)(JNIEnv* e,jclass,jlong handle,jstring action,jstring value,jfloat number) {
 try {auto s=reinterpret_cast<Session*>(handle);auto a=str(e,action);
   if(a=="unload")s->model.reset();
   else if(a=="mouth")s->mouth=std::clamp(float(number),0.f,1.f);
   else if(a=="zoom")s->zoom=std::clamp(float(number),.4f,3.f);
   else if(a=="x")s->x=std::clamp(float(number),-2.f,2.f);
   else if(a=="y")s->y=std::clamp(float(number),-2.f,2.f);
   else if(a=="clock")s->previous=std::chrono::steady_clock::now();
   else if(!s->model)throw std::runtime_error("Model not loaded");
   else if(a=="automaticPose")s->model->resumeAutomaticPose();
   else if(a=="reset")s->model->reset();
   else if(a=="expression")s->model->expression(str(e,value));
   else if(a=="motion")s->model->motion(str(e,value));
   else throw std::runtime_error("Unknown command");
 }catch(const std::exception& x){error(e,x);}
}
extern "C" JNIEXPORT jobjectArray JNICALL JNI_METHOD(nativeParameterIds)(JNIEnv* env, jclass, jlong handle) {
 const auto& model = reinterpret_cast<Session*>(handle)->model;
 const int count = model ? model->parameters().GetParameterCount() : 0;
 const auto ids = env->NewObjectArray(count, env->FindClass("java/lang/String"), nullptr);
 if (!ids) return nullptr;
 for (int i = 0; i < count; ++i) {
   const auto id = env->NewStringUTF(model->parameters().GetParameterId(i)->GetString().GetRawString());
   if (!id) return nullptr;
   env->SetObjectArrayElement(ids, i, id);
   env->DeleteLocalRef(id);
 }
 return ids;
}

// Four entries per real MOC parameter: minimum, maximum, default and current.
extern "C" JNIEXPORT jfloatArray JNICALL JNI_METHOD(nativeParameterData)(JNIEnv* env, jclass, jlong handle) {
 try {
   const auto& model = reinterpret_cast<Session*>(handle)->model;
   std::vector<float> data;
   if (model) {
     auto& parameters = model->parameters();
     for (int i = 0; i < parameters.GetParameterCount(); ++i) {
       data.insert(data.end(), {parameters.GetParameterMinimumValue(i), parameters.GetParameterMaximumValue(i),
                                parameters.GetParameterDefaultValue(i), parameters.GetParameterValue(i)});
     }
   }
   const auto result = env->NewFloatArray(data.size());
   if (result && !data.empty()) env->SetFloatArrayRegion(result, 0, data.size(), data.data());
   return result;
 } catch (const std::exception& exception) {
   error(env, exception);
   return nullptr;
 }
}

extern "C" JNIEXPORT void JNICALL JNI_METHOD(nativeSetPose)(JNIEnv* env, jclass, jlong handle, jfloatArray updates) {
 try {
   const auto& model = reinterpret_cast<Session*>(handle)->model;
   if (!model) throw std::runtime_error("Model not loaded");
   std::vector<float> values(env->GetArrayLength(updates));
   if (!values.empty()) env->GetFloatArrayRegion(updates, 0, values.size(), values.data());
   if (!env->ExceptionCheck()) model->setPose(values);
 } catch (const std::exception& exception) {
   error(env, exception);
 }
}

extern "C" JNIEXPORT jint JNICALL JNI_METHOD(nativePosePart)(JNIEnv* env, jclass, jlong handle, jobjectArray parts, jint selected) {
 try {
   auto& model = reinterpret_cast<Session*>(handle)->model->parameters();
   for (int i = 0; i < env->GetArrayLength(parts); ++i) {
     const auto part = static_cast<jstring>(env->GetObjectArrayElement(parts, i));
     const auto id = CubismFramework::GetIdManager()->GetId(str(env, part).c_str());
     env->DeleteLocalRef(part);
     if (selected >= 0) {
       model.SetParameterValue(id, i == selected ? 1.0f : 0.0f);
     } else if (model.GetParameterValue(id) > 0.001f) {
       return i;
     }
   }
   return 0;
 } catch (const std::exception& exception) {
   error(env, exception);
   return 0;
 }
}
extern "C" JNIEXPORT void JNICALL JNI_METHOD(nativeFrame)(JNIEnv* e,jclass,jlong h) {
 try{reinterpret_cast<Session*>(h)->frame();}catch(const std::exception& x){error(e,x);}
}
extern "C" JNIEXPORT void JNICALL JNI_METHOD(nativeDestroy)(JNIEnv*,jclass,jlong h) { delete reinterpret_cast<Session*>(h); }
