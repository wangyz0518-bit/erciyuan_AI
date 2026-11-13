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
#include <cstdlib>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
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
 int headIndices[3]={-1,-1,-1};
 float headValues[3]={0,0,0};
 bool headManual[3]={false,false,false};
 public:
 ~Model() override {
   _motionManager->StopAllMotions(); _expressionManager->StopAllMotions();
   for(auto& p:motions) ACubismMotion::Delete(p.second);
   for(auto& p:expressions) ACubismMotion::Delete(p.second);
   DeleteRenderer();
   if(!textures.empty()) glDeleteTextures(textures.size(),textures.data());
 }
 void load(const std::string& path,int w,int h) {
   auto json=read(path); settings=std::make_unique<CubismModelSettingJson>(json.data(),json.size());
   std::string dir=path.substr(0,path.find_last_of('/')+1);
   auto moc=read(dir+settings->GetModelFileName()); LoadModel(moc.data(),moc.size(),true);
   if(!_model) throw std::runtime_error("MOC3 consistency check failed");
   const char* headIds[]={"ParamAngleX","ParamAngleY","ParamAngleZ"};
   // GetParameterIndex creates synthetic entries for absent IDs; inspect real IDs instead.
   for(int axis=0;axis<3;++axis) {
     auto id=CubismFramework::GetIdManager()->GetId(headIds[axis]);
     for(int i=0;i<_model->GetParameterCount();++i) if(_model->GetParameterId(i)==id) {
       headIndices[axis]=i;headValues[axis]=_model->GetParameterDefaultValue(i);break;
     }
   }
   auto optional=[&](const char* file,auto fn) { if(file && *file) {auto b=read(dir+file);fn(b);} };
   optional(settings->GetPhysicsFileName(),[&](auto& b){LoadPhysics(b.data(),b.size());});
   optional(settings->GetPoseFileName(),[&](auto& b){LoadPose(b.data(),b.size());});
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
 }
 void expression(const std::string& id) {
   auto it=expressions.find(id); if(it==expressions.end()) throw std::runtime_error("Unsupported expression: "+id);
   _expressionManager->StartMotion(it->second,false);
 }
 void motion(const std::string& id) {
   auto it=motions.find(id); if(it==motions.end()) throw std::runtime_error("Unsupported motion: "+id);
   _motionManager->StartMotionPriority(it->second,false,3);
 }
 void head(int axis,float normalized) {
   const int i=headIndices[axis];
   if(i<0)throw std::runtime_error("Head parameter not supported by this model");
   const float center=_model->GetParameterDefaultValue(i);
   normalized=std::clamp(normalized,-1.f,1.f);
   headValues[axis]=center+normalized*(normalized<0?center-_model->GetParameterMinimumValue(i):_model->GetParameterMaximumValue(i)-center);
   headManual[axis]=true;
 }
 void applyHead() {
   for(int axis=0;axis<3;++axis)if(headManual[axis])_model->SetParameterValue(headIndices[axis],headValues[axis]);
 }
 std::string headInfo() {
   std::string json="{";const char* keys[]={"headX","headY","headZ"};bool first=true;
   for(int axis=0;axis<3;++axis) {
     const int i=headIndices[axis];if(i<0)continue;
     if(!first)json+=",";first=false;
     json+=std::string("\"")+keys[axis]+"\":{\"min\":"+std::to_string(_model->GetParameterMinimumValue(i))+
       ",\"max\":"+std::to_string(_model->GetParameterMaximumValue(i))+",\"default\":"+std::to_string(_model->GetParameterDefaultValue(i))+
       ",\"value\":"+std::to_string(_model->GetParameterValue(i))+",\"manual\":"+(headManual[axis]?"true":"false")+"}";
   }
   return json+"}";
 }
 void draw(float dt,int w,int h,float mouth,float zoom,float x,float y) {
   _model->LoadParameters();
   if(_motionManager->IsFinished() && !idle.empty()) _motionManager->StartMotionPriority(motions.at(idle),false,1);
   bool moved=_motionManager->UpdateMotion(_model,dt); _model->SaveParameters();
   if(!moved && _eyeBlink) _eyeBlink->UpdateParameters(_model,dt);
   _expressionManager->UpdateMotion(_model,dt);
   applyHead(); // Feed head motion into hair/accessory physics.
   if(_physics) _physics->Evaluate(_model,dt);
   if(_pose) _pose->UpdateParameters(_model,dt);
   applyHead(); // Keep manual pose stable even when a motion/physics writes these IDs.
   for(int i=0;i<settings->GetLipSyncParameterCount();++i)
     _model->SetParameterValue(settings->GetLipSyncParameterId(i),mouth);
   _model->Update();
   _modelMatrix->SetHeight(2.0f);
   CubismMatrix44 m; m.Translate(x,y); m.Scale(zoom*float(h)/w,zoom); m.MultiplyByMatrix(_modelMatrix);
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
extern "C" JNIEXPORT void JNICALL JNI_METHOD(nativeCommand)(JNIEnv* e,jclass,jlong handle,jstring action,jstring value,jfloat number) {
 try {auto s=reinterpret_cast<Session*>(handle);auto a=str(e,action);
   if(a=="unload")s->model.reset();
   else if(a=="mouth")s->mouth=std::clamp(float(number),0.f,1.f);
   else if(a=="zoom")s->zoom=std::clamp(float(number),.4f,3.f);
   else if(a=="x")s->x=std::clamp(float(number),-2.f,2.f);
   else if(a=="y")s->y=std::clamp(float(number),-2.f,2.f);
   else if(!s->model)throw std::runtime_error("Model not loaded");
   else if(a=="headX" || a=="headY" || a=="headZ")s->model->head(a.back()-'X',number);
   else if(a=="expression")s->model->expression(str(e,value));
   else if(a=="motion")s->model->motion(str(e,value));
   else throw std::runtime_error("Unknown command");
 }catch(const std::exception& x){error(e,x);}
}
extern "C" JNIEXPORT jstring JNICALL JNI_METHOD(nativeHeadInfo)(JNIEnv* e,jclass,jlong h) {
 try {auto s=reinterpret_cast<Session*>(h);return e->NewStringUTF(s->model?s->model->headInfo().c_str():"{}");}
 catch(const std::exception& x){error(e,x);return nullptr;}
}
extern "C" JNIEXPORT void JNICALL JNI_METHOD(nativeFrame)(JNIEnv* e,jclass,jlong h) {
 try{reinterpret_cast<Session*>(h)->frame();}catch(const std::exception& x){error(e,x);}
}
extern "C" JNIEXPORT void JNICALL JNI_METHOD(nativeDestroy)(JNIEnv*,jclass,jlong h) { delete reinterpret_cast<Session*>(h); }
