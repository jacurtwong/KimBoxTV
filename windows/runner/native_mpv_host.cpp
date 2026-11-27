#include "native_mpv_host.h"

#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>

namespace {

constexpr const wchar_t kHostClassName[] = L"KIMBOX_NATIVE_MPV_HOST";
constexpr const wchar_t kSurfaceClassName[] = L"KIMBOX_NATIVE_MPV_SURFACE";
constexpr int kMpvFormatNone = 0;
constexpr int kMpvFormatString = 1;
constexpr int kMpvFormatFlag = 3;
constexpr int kMpvFormatInt64 = 4;
constexpr int kMpvFormatDouble = 5;
constexpr int kMpvFormatNodeArray = 7;
constexpr int kMpvFormatNodeMap = 8;
constexpr int kMpvFormatByteArray = 9;

constexpr int kMpvEventNone = 0;
constexpr int kMpvEventLogMessage = 2;
constexpr int kMpvEventStartFile = 6;
constexpr int kMpvEventEndFile = 7;

struct MpvNode;
struct MpvByteArray {
  void* data;
  size_t size;
};

struct MpvNodeList {
  int num;
  MpvNode* values;
  char** keys;
};

struct MpvNode {
  union {
    char* string;
    int flag;
    int64_t int64;
    double double_;
    MpvNodeList* list;
    MpvByteArray* ba;
  } u;
  int format;
};

struct MpvEventLogMessage {
  const char* prefix;
  const char* level;
  const char* text;
  int log_level;
};

struct MpvEventEndFile {
  int reason;
  int error;
  int64_t playlist_entry_id;
  int64_t playlist_insert_id;
  int playlist_insert_num_entries;
};

struct MpvEvent {
  int event_id;
  int error;
  uint64_t reply_userdata;
  void* data;
};

using FnMpvCreate = mpv_handle* (*)();
using FnMpvInitialize = int (*)(mpv_handle*);
using FnMpvTerminateDestroy = void (*)(mpv_handle*);
using FnMpvSetOption = int (*)(mpv_handle*, const char*, int, void*);
using FnMpvSetOptionString = int (*)(mpv_handle*, const char*, const char*);
using FnMpvSetProperty = int (*)(mpv_handle*, const char*, int, void*);
using FnMpvSetPropertyString = int (*)(mpv_handle*, const char*, const char*);
using FnMpvGetProperty = int (*)(mpv_handle*, const char*, int, void*);
using FnMpvGetPropertyString = char* (*)(mpv_handle*, const char*);
using FnMpvFree = void (*)(void*);
using FnMpvCommand = int (*)(mpv_handle*, const char**);
using FnMpvCommandNode = int (*)(mpv_handle*, MpvNode*, MpvNode*);
using FnMpvFreeNodeContents = void (*)(MpvNode*);
using FnMpvWaitEvent = MpvEvent* (*)(mpv_handle*, double);
using FnMpvWakeup = void (*)(mpv_handle*);
using FnMpvRequestLogMessages = int (*)(mpv_handle*, const char*);

struct MpvProcs {
  FnMpvCreate create = nullptr;
  FnMpvInitialize initialize = nullptr;
  FnMpvTerminateDestroy terminate_destroy = nullptr;
  FnMpvSetOption set_option = nullptr;
  FnMpvSetOptionString set_option_string = nullptr;
  FnMpvSetProperty set_property = nullptr;
  FnMpvSetPropertyString set_property_string = nullptr;
  FnMpvGetProperty get_property = nullptr;
  FnMpvGetPropertyString get_property_string = nullptr;
  FnMpvFree free = nullptr;
  FnMpvCommand command = nullptr;
  FnMpvCommandNode command_node = nullptr;
  FnMpvFreeNodeContents free_node_contents = nullptr;
  FnMpvWaitEvent wait_event = nullptr;
  FnMpvWakeup wakeup = nullptr;
  FnMpvRequestLogMessages request_log_messages = nullptr;

  bool Load(HMODULE mod) {
    if (!mod) return false;
#define LOAD_MPV(field, sym)                                     \
  field = reinterpret_cast<decltype(field)>(GetProcAddress(mod, sym)); \
  if (!field) return false;
    LOAD_MPV(create, "mpv_create");
    LOAD_MPV(initialize, "mpv_initialize");
    LOAD_MPV(terminate_destroy, "mpv_terminate_destroy");
    LOAD_MPV(set_option, "mpv_set_option");
    LOAD_MPV(set_option_string, "mpv_set_option_string");
    LOAD_MPV(set_property, "mpv_set_property");
    LOAD_MPV(set_property_string, "mpv_set_property_string");
    LOAD_MPV(get_property, "mpv_get_property");
    LOAD_MPV(get_property_string, "mpv_get_property_string");
    LOAD_MPV(free, "mpv_free");
    LOAD_MPV(command, "mpv_command");
    LOAD_MPV(wait_event, "mpv_wait_event");
    LOAD_MPV(wakeup, "mpv_wakeup");
    LOAD_MPV(request_log_messages, "mpv_request_log_messages");
#undef LOAD_MPV
    command_node = reinterpret_cast<FnMpvCommandNode>(
        GetProcAddress(mod, "mpv_command_node"));
    free_node_contents = reinterpret_cast<FnMpvFreeNodeContents>(
        GetProcAddress(mod, "mpv_free_node_contents"));
    return true;
  }
};

MpvProcs g_procs;

const char* HwdecValueForMode(const std::string& mode) {
  if (mode == "hw") return "d3d11va,d3d11va-copy,dxva2-copy";
  if (mode == "sw") return "no";
  return "auto-safe";
}

bool GetIntArg(const flutter::EncodableMap* args, const char* key, int* out) {
  if (!args) return false;
  auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end()) return false;
  if (std::holds_alternative<int32_t>(it->second)) {
    *out = std::get<int32_t>(it->second);
    return true;
  }
  if (std::holds_alternative<int64_t>(it->second)) {
    *out = static_cast<int>(std::get<int64_t>(it->second));
    return true;
  }
  return false;
}

bool GetDoubleArg(const flutter::EncodableMap* args,
                  const char* key,
                  double* out) {
  if (!args) return false;
  auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end()) return false;
  if (std::holds_alternative<double>(it->second)) {
    *out = std::get<double>(it->second);
    return true;
  }
  if (std::holds_alternative<int32_t>(it->second)) {
    *out = static_cast<double>(std::get<int32_t>(it->second));
    return true;
  }
  if (std::holds_alternative<int64_t>(it->second)) {
    *out = static_cast<double>(std::get<int64_t>(it->second));
    return true;
  }
  return false;
}

bool GetStringArg(const flutter::EncodableMap* args,
                  const char* key,
                  std::string* out) {
  if (!args) return false;
  auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end()) return false;
  if (const auto* s = std::get_if<std::string>(&it->second)) {
    *out = *s;
    return true;
  }
  return false;
}

bool GetBoolArg(const flutter::EncodableMap* args,
                const char* key,
                bool* out) {
  if (!args) return false;
  auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end()) return false;
  if (const auto* b = std::get_if<bool>(&it->second)) {
    *out = *b;
    return true;
  }
  return false;
}

}  // namespace

NativeMpvHost::NativeMpvHost(HWND parent_hwnd, HWND flutter_hwnd)
    : parent_hwnd_(parent_hwnd), flutter_hwnd_(flutter_hwnd) {}

NativeMpvHost::~NativeMpvHost() {
  DetachAndDispose();
}

void NativeMpvHost::AttachChannel(
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel) {
  channel_ = std::move(channel);
}

void NativeMpvHost::DetachAndDispose() {
  channel_.reset();
  DestroyMpvInstance();
  if (mpv_hwnd_) {
    ::DestroyWindow(mpv_hwnd_);
    mpv_hwnd_ = nullptr;
  }
  if (host_hwnd_) {
    ::DestroyWindow(host_hwnd_);
    host_hwnd_ = nullptr;
  }
  if (black_brush_) {
    ::DeleteObject(black_brush_);
    black_brush_ = nullptr;
  }
}

bool NativeMpvHost::EnsureWindowCreated() {
  if (host_hwnd_ && mpv_hwnd_) return true;
  if (!parent_hwnd_) return false;

  HBRUSH black = static_cast<HBRUSH>(::GetStockObject(BLACK_BRUSH));

  static bool class_registered = false;
  if (!class_registered) {
    WNDCLASSW wc{};
    wc.style = CS_DBLCLKS | CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = NativeMpvHost::HostWndProc;
    wc.hInstance = ::GetModuleHandleW(nullptr);
    wc.hCursor = ::LoadCursorW(nullptr, IDC_ARROW);
    wc.hbrBackground = black;
    wc.lpszClassName = kHostClassName;
    ::RegisterClassW(&wc);

    WNDCLASSW swc{};
    swc.style = CS_HREDRAW | CS_VREDRAW;
    swc.lpfnWndProc = NativeMpvHost::SurfaceWndProc;
    swc.hInstance = ::GetModuleHandleW(nullptr);
    swc.hCursor = ::LoadCursorW(nullptr, IDC_ARROW);
    swc.hbrBackground = black;
    swc.lpszClassName = kSurfaceClassName;
    ::RegisterClassW(&swc);

    class_registered = true;
  }

  if (!host_hwnd_) {
    host_hwnd_ = ::CreateWindowExW(
        0, kHostClassName, L"",
        WS_CHILD | WS_CLIPCHILDREN | WS_CLIPSIBLINGS, 0, 0, 1, 1,
        parent_hwnd_, nullptr, ::GetModuleHandleW(nullptr), this);
    if (!host_hwnd_) return false;
  }

  if (!mpv_hwnd_) {
    // Dedicated black-backed class avoids white/gray STATIC background flashes before vo=gpu presents;
    // WS_DISABLED routes all mouse/focus events to host_hwnd_.
    mpv_hwnd_ = ::CreateWindowExW(
        0, kSurfaceClassName, L"", WS_CHILD | WS_VISIBLE | WS_DISABLED, 0, 0, 1,
        1, host_hwnd_, nullptr, ::GetModuleHandleW(nullptr), nullptr);
    if (!mpv_hwnd_) return false;
  }

  return true;
}

bool NativeMpvHost::EnsureMpvLoaded() {
  if (libmpv_) return true;
  libmpv_ = ::GetModuleHandleW(L"libmpv-2.dll");
  if (!libmpv_) {
    libmpv_ = ::LoadLibraryW(L"libmpv-2.dll");
  }
  if (!libmpv_) return false;
  return g_procs.Load(libmpv_);
}

bool NativeMpvHost::EnsureMpvCreated() {
  if (!EnsureWindowCreated()) return false;
  if (!EnsureMpvLoaded()) return false;

  std::lock_guard<std::mutex> lock(mpv_mu_);
  if (ctx_) return true;

  auto tryInit = [&](const char* gpu_api) -> mpv_handle* {
    mpv_handle* c = g_procs.create();
    if (!c) return nullptr;

    int64_t wid = reinterpret_cast<intptr_t>(mpv_hwnd_);
    g_procs.set_option(c, "wid", kMpvFormatInt64, &wid);
    g_procs.set_option_string(c, "vo", "gpu");
    if (gpu_api != nullptr && gpu_api[0] != '\0') {
      g_procs.set_option_string(c, "gpu-api", gpu_api);
    }
    g_procs.set_option_string(c, "hwdec", HwdecValueForMode(hwdec_mode_));
    g_procs.set_option_string(c, "idle", "yes");
    g_procs.set_option_string(c, "keep-open", "no");
    g_procs.set_option_string(c, "keepaspect", "yes");
    g_procs.set_option_string(c, "input-default-bindings", "no");
    g_procs.set_option_string(c, "input-vo-keyboard", "no");
    g_procs.set_option_string(c, "input-cursor", "no");
    g_procs.set_option_string(c, "osc", "no");
    g_procs.set_option_string(c, "osd-level", "0");
    g_procs.set_option_string(c, "audio-client-name", "KimBoxTV");
    g_procs.set_option_string(c, "audio-pitch-correction", "no");
    g_procs.set_option_string(c, "sub-auto", "fuzzy");
    g_procs.request_log_messages(c, "info");

    if (g_procs.initialize(c) < 0) {
      g_procs.terminate_destroy(c);
      return nullptr;
    }
    return c;
  };

  ctx_ = tryInit("d3d11");
  {
    std::lock_guard<std::mutex> ml(meta_mu_);
    render_backend_ = ctx_ ? "native_d3d11" : "native_gpu";
  }
  if (!ctx_) {
    ctx_ = tryInit("auto");
    if (ctx_) {
      std::lock_guard<std::mutex> ml(meta_mu_);
      render_backend_ = "native_gpu";
    }
  }
  if (!ctx_) return false;

  stop_events_.store(false);
  event_thread_ = std::thread(&NativeMpvHost::EventLoop, this);
  return true;
}

void NativeMpvHost::DestroyMpvInstance() {
  stop_events_.store(true);
  {
    std::lock_guard<std::mutex> lock(mpv_mu_);
    if (ctx_ && g_procs.wakeup) {
      g_procs.wakeup(ctx_);
    }
  }
  if (event_thread_.joinable()) {
    event_thread_.join();
  }
  std::lock_guard<std::mutex> lock(mpv_mu_);
  if (ctx_ && g_procs.terminate_destroy) {
    g_procs.terminate_destroy(ctx_);
    ctx_ = nullptr;
  }
  playback_started_.store(false);
  eof_reached_.store(false);
}

void NativeMpvHost::EventLoop() {
  while (!stop_events_.load()) {
    mpv_handle* c = nullptr;
    {
      std::lock_guard<std::mutex> lock(mpv_mu_);
      c = ctx_;
    }
    if (!c || !g_procs.wait_event) break;
    MpvEvent* ev = g_procs.wait_event(c, 0.25);
    if (!ev || stop_events_.load()) break;
    if (ev->event_id == kMpvEventNone) continue;

    if (ev->event_id == kMpvEventLogMessage && ev->data) {
      const auto* msg = static_cast<const MpvEventLogMessage*>(ev->data);
      if (msg->text && msg->prefix &&
          (std::strcmp(msg->prefix, "vo/gpu") == 0 ||
           std::strcmp(msg->prefix, "vo/gpu/d3d11") == 0 ||
           std::strcmp(msg->prefix, "vo/gpu/opengl") == 0)) {
        if (std::strstr(msg->text, "d3d11") != nullptr ||
            std::strcmp(msg->prefix, "vo/gpu/d3d11") == 0) {
          std::lock_guard<std::mutex> ml(meta_mu_);
          render_backend_ = "native_d3d11";
        } else if (std::strstr(msg->text, "opengl") != nullptr ||
                   std::strcmp(msg->prefix, "vo/gpu/opengl") == 0) {
          std::lock_guard<std::mutex> ml(meta_mu_);
          render_backend_ = "native_gl";
        }
      }
    } else if (ev->event_id == kMpvEventStartFile) {
      eof_reached_.store(false);
    } else if (ev->event_id == kMpvEventEndFile && ev->data) {
      const auto* ef = static_cast<const MpvEventEndFile*>(ev->data);
      if (ef->reason == 0 /* EOF */ || ef->reason == 4 /* ERROR */) {
        eof_reached_.store(true);
        if (host_hwnd_) {
          ::PostMessageW(host_hwnd_, kWmMpvEnded,
                         static_cast<WPARAM>(ef->reason), 0);
        }
      }
    }
  }
}

LRESULT CALLBACK NativeMpvHost::HostWndProc(HWND hwnd,
                                            UINT msg,
                                            WPARAM wp,
                                            LPARAM lp) {
  if (msg == WM_NCCREATE) {
    auto* cs = reinterpret_cast<CREATESTRUCTW*>(lp);
    auto* self = static_cast<NativeMpvHost*>(cs->lpCreateParams);
    ::SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    return TRUE;
  }
  auto* self = reinterpret_cast<NativeMpvHost*>(
      ::GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (self) {
    return self->HandleHostMessage(hwnd, msg, wp, lp);
  }
  return ::DefWindowProcW(hwnd, msg, wp, lp);
}

LRESULT CALLBACK NativeMpvHost::SurfaceWndProc(HWND hwnd,
                                                UINT msg,
                                                WPARAM wp,
                                                LPARAM lp) {
  switch (msg) {
    case WM_ERASEBKGND: {
      HDC hdc = reinterpret_cast<HDC>(wp);
      if (hdc) {
        RECT rc{};
        ::GetClientRect(hwnd, &rc);
        ::FillRect(hdc, &rc, static_cast<HBRUSH>(::GetStockObject(BLACK_BRUSH)));
      }
      return 1;
    }
    case WM_PAINT: {
      PAINTSTRUCT ps{};
      HDC hdc = ::BeginPaint(hwnd, &ps);
      if (hdc) {
        ::FillRect(hdc, &ps.rcPaint,
                   static_cast<HBRUSH>(::GetStockObject(BLACK_BRUSH)));
      }
      ::EndPaint(hwnd, &ps);
      return 0;
    }
  }
  return ::DefWindowProcW(hwnd, msg, wp, lp);
}

LRESULT NativeMpvHost::HandleHostMessage(HWND hwnd,
                                           UINT msg,
                                           WPARAM wp,
                                           LPARAM lp) {
  switch (msg) {
    case WM_ERASEBKGND: {
      HDC hdc = reinterpret_cast<HDC>(wp);
      if (hdc) {
        RECT rc{};
        ::GetClientRect(hwnd, &rc);
        ::FillRect(hdc, &rc, static_cast<HBRUSH>(::GetStockObject(BLACK_BRUSH)));
      }
      return 1;
    }
    case WM_CTLCOLORSTATIC: {
      return reinterpret_cast<LRESULT>(::GetStockObject(BLACK_BRUSH));
    }
    case WM_SIZE: {
      const int w = LOWORD(lp);
      const int h = HIWORD(lp);
      if (mpv_hwnd_ && w > 0 && h > 0) {
        ::MoveWindow(mpv_hwnd_, 0, 0, w, h, FALSE);
      }
      return 0;
    }
    case WM_SETCURSOR: {
      if (LOWORD(lp) == HTCLIENT) {
        ::SetCursor(hide_cursor_ ? nullptr : ::LoadCursorW(nullptr, IDC_ARROW));
        return TRUE;
      }
      break;
    }
    case WM_LBUTTONDOWN: {
      if (!visible_ || !playback_started_.load()) return 0;
      if (flutter_hwnd_) ::SetFocus(flutter_hwnd_);
      return 0;
    }
    case WM_LBUTTONUP: {
      if (!visible_ || !playback_started_.load()) {
        ::KillTimer(hwnd, kTapTimerId);
        return 0;
      }
      if (flutter_hwnd_) ::SetFocus(flutter_hwnd_);
      UINT delay = ::GetDoubleClickTime();
      if (delay > 260) delay = 260;
      ::SetTimer(hwnd, kTapTimerId, delay, nullptr);
      return 0;
    }
    case WM_LBUTTONDBLCLK: {
      ::KillTimer(hwnd, kTapTimerId);
      if (!visible_ || !playback_started_.load()) return 0;
      if (flutter_hwnd_) ::SetFocus(flutter_hwnd_);
      if (channel_) {
        channel_->InvokeMethod("onDoubleTap", nullptr);
      }
      return 0;
    }
    case WM_TIMER: {
      if (wp == kTapTimerId) {
        ::KillTimer(hwnd, kTapTimerId);
        if (visible_ && playback_started_.load() && channel_) {
          channel_->InvokeMethod("onTap", nullptr);
        }
        return 0;
      }
      break;
    }
    case WM_MOUSEMOVE: {
      if (!visible_ || !playback_started_.load()) return 0;
      POINT pt{static_cast<short>(LOWORD(lp)), static_cast<short>(HIWORD(lp))};
      if (pt.x != last_mouse_pt_.x || pt.y != last_mouse_pt_.y) {
        last_mouse_pt_ = pt;
        const ULONGLONG now = ::GetTickCount64();
        if (now - last_move_tick_ >= 60) {
          last_move_tick_ = now;
          if (channel_) {
            channel_->InvokeMethod("onMouseMove", nullptr);
          }
        }
      }
      return 0;
    }
    case kWmMpvEnded: {
      if (channel_) {
        channel_->InvokeMethod(
            "onEndFile",
            std::make_unique<flutter::EncodableValue>(static_cast<int>(wp)));
      }
      return 0;
    }
  }
  return ::DefWindowProcW(hwnd, msg, wp, lp);
}

void NativeMpvHost::SetViewport(int x,
                                int y,
                                int w,
                                int h,
                                bool visible,
                                bool hide_cursor) {
  if (!EnsureWindowCreated()) return;
  hide_cursor_ = hide_cursor;
  if (w < 1) w = 1;
  if (h < 1) h = 1;
  viewport_w_ = w;
  viewport_h_ = h;
  visible_ = visible;

  if (visible) {
    ::SetWindowPos(host_hwnd_, HWND_TOP, x, y, w, h,
                   SWP_NOACTIVATE | SWP_SHOWWINDOW);
    if (mpv_hwnd_) {
      ::MoveWindow(mpv_hwnd_, 0, 0, w, h, FALSE);
    }
    if (hide_cursor_) {
      POINT pt{};
      if (::GetCursorPos(&pt) && ::WindowFromPoint(pt) == host_hwnd_) {
        ::SetCursor(nullptr);
      }
    }
  } else {
    if (host_hwnd_) {
      ::KillTimer(host_hwnd_, kTapTimerId);
      ::ShowWindow(host_hwnd_, SW_HIDE);
    }
  }
}

bool NativeMpvHost::OpenMedia(const std::string& url,
                              const std::string& title,
                              double start_sec,
                              int cache_secs,
                              const std::vector<std::string>& headers,
                              const std::string& hwdec_mode) {
  hwdec_mode_ = hwdec_mode.empty() ? "auto" : hwdec_mode;
  if (!EnsureMpvCreated()) return false;

  std::lock_guard<std::mutex> lock(mpv_mu_);
  if (!ctx_) return false;

  g_procs.set_property_string(ctx_, "hwdec", HwdecValueForMode(hwdec_mode_));
  if (!title.empty()) {
    g_procs.set_property_string(ctx_, "force-media-title", title.c_str());
  }

  const int secs = std::clamp(cache_secs, 5, 600);
  char secs_buf[32];
  std::snprintf(secs_buf, sizeof(secs_buf), "%d", secs);
  g_procs.set_property_string(ctx_, "cache", "yes");
  g_procs.set_property_string(ctx_, "cache-secs", secs_buf);
  const int64_t max_bytes = std::clamp<int64_t>(
      static_cast<int64_t>(secs * 0.75 * 1024 * 1024), 32LL * 1024 * 1024,
      512LL * 1024 * 1024);
  char bytes_buf[32];
  std::snprintf(bytes_buf, sizeof(bytes_buf), "%lld",
                static_cast<long long>(max_bytes));
  g_procs.set_property_string(ctx_, "demuxer-max-bytes", bytes_buf);
  std::snprintf(bytes_buf, sizeof(bytes_buf), "%lld",
                static_cast<long long>(max_bytes / 2));
  g_procs.set_property_string(ctx_, "demuxer-max-back-bytes", bytes_buf);

  // Set custom HTTP headers using MPV_FORMAT_NODE_ARRAY to safely preserve commas/colons.
  if (headers.empty()) {
    g_procs.set_property_string(ctx_, "http-header-fields", "");
  } else {
    std::vector<MpvNode> nodes(headers.size());
    for (size_t i = 0; i < headers.size(); ++i) {
      nodes[i].format = kMpvFormatString;
      nodes[i].u.string = const_cast<char*>(headers[i].c_str());
    }
    MpvNodeList list{};
    list.num = static_cast<int>(nodes.size());
    list.values = nodes.data();
    list.keys = nullptr;
    MpvNode root{};
    root.format = kMpvFormatNodeArray;
    root.u.list = &list;
    g_procs.set_property(ctx_, "http-header-fields", kMpvFormatNodeArray, &root);
  }

  int pause_flag = 0;
  g_procs.set_property(ctx_, "pause", kMpvFormatFlag, &pause_flag);

  eof_reached_.store(false);
  playback_started_.store(true);

  if (start_sec > 0.5) {
    char opt_buf[64];
    std::snprintf(opt_buf, sizeof(opt_buf), "start=+%.3f",
                  std::clamp(start_sec, 0.0, 864000.0));
    const char* cmd[] = {"loadfile", url.c_str(), "replace", opt_buf, nullptr};
    return g_procs.command(ctx_, cmd) >= 0;
  }
  const char* cmd[] = {"loadfile", url.c_str(), "replace", nullptr};
  return g_procs.command(ctx_, cmd) >= 0;
}

void NativeMpvHost::ApplyHwdec(const std::string& mode) {
  hwdec_mode_ = mode.empty() ? "auto" : mode;
  std::lock_guard<std::mutex> lock(mpv_mu_);
  if (ctx_) {
    g_procs.set_property_string(ctx_, "hwdec", HwdecValueForMode(hwdec_mode_));
  }
}

void NativeMpvHost::StopPlayback() {
  {
    std::lock_guard<std::mutex> lock(mpv_mu_);
    playback_started_.store(false);
    eof_reached_.store(false);
    if (ctx_) {
      const char* cmd[] = {"stop", nullptr};
      g_procs.command(ctx_, cmd);
    }
  }
  visible_ = false;
  if (host_hwnd_) {
    ::KillTimer(host_hwnd_, kTapTimerId);
    ::ShowWindow(host_hwnd_, SW_HIDE);
  }
}

void NativeMpvHost::SetPaused(bool paused) {
  std::lock_guard<std::mutex> lock(mpv_mu_);
  if (!ctx_) return;
  int flag = paused ? 1 : 0;
  g_procs.set_property(ctx_, "pause", kMpvFormatFlag, &flag);
}

void NativeMpvHost::TogglePause() {
  std::lock_guard<std::mutex> lock(mpv_mu_);
  if (!ctx_) return;
  const char* cmd[] = {"cycle", "pause", nullptr};
  g_procs.command(ctx_, cmd);
}

void NativeMpvHost::SeekAbsolute(double seconds) {
  std::lock_guard<std::mutex> lock(mpv_mu_);
  if (!ctx_) return;
  char pos_buf[48];
  std::snprintf(pos_buf, sizeof(pos_buf), "%.3f", std::max(0.0, seconds));
  const char* cmd[] = {"seek", pos_buf, "absolute", nullptr};
  g_procs.command(ctx_, cmd);
}

void NativeMpvHost::SetVolume(double volume) {
  std::lock_guard<std::mutex> lock(mpv_mu_);
  if (!ctx_) return;
  double v = std::clamp(volume, 0.0, 100.0);
  g_procs.set_property(ctx_, "volume", kMpvFormatDouble, &v);
}

void NativeMpvHost::SetMute(bool muted) {
  std::lock_guard<std::mutex> lock(mpv_mu_);
  if (!ctx_) return;
  int flag = muted ? 1 : 0;
  g_procs.set_property(ctx_, "mute", kMpvFormatFlag, &flag);
}

void NativeMpvHost::SetRate(double rate) {
  std::lock_guard<std::mutex> lock(mpv_mu_);
  if (!ctx_) return;
  double r = std::clamp(rate, 0.25, 4.0);
  g_procs.set_property(ctx_, "speed", kMpvFormatDouble, &r);
}

void NativeMpvHost::SetSubTrack(const std::string& id) {
  std::lock_guard<std::mutex> lock(mpv_mu_);
  if (!ctx_) return;
  const char* val = (id.empty() || id == "0") ? "no" : id.c_str();
  g_procs.set_property_string(ctx_, "sid", val);
}

void NativeMpvHost::SetAudioTrack(const std::string& id) {
  std::lock_guard<std::mutex> lock(mpv_mu_);
  if (!ctx_ || id.empty()) return;
  g_procs.set_property_string(ctx_, "aid", id.c_str());
}

void NativeMpvHost::AddExternalSubtitle(const std::string& path) {
  std::lock_guard<std::mutex> lock(mpv_mu_);
  if (!ctx_ || path.empty()) return;
  const char* cmd[] = {"sub-add", path.c_str(), "select", nullptr};
  g_procs.command(ctx_, cmd);
}

void NativeMpvHost::SetOsdOverlay(int id,
                                  const std::string& ass_data,
                                  int res_x,
                                  int res_y) {
  std::lock_guard<std::mutex> lock(mpv_mu_);
  if (!ctx_) return;
  char id_buf[16];
  char rx_buf[16];
  char ry_buf[16];
  std::snprintf(id_buf, sizeof(id_buf), "%d", id);
  if (ass_data.empty()) {
    const char* cmd[] = {"osd-overlay", id_buf, "none", "", "0",
                         "0",           "0",    "no",   "no", nullptr};
    g_procs.command(ctx_, cmd);
    return;
  }
  std::snprintf(rx_buf, sizeof(rx_buf), "%d", res_x > 0 ? res_x : 1280);
  std::snprintf(ry_buf, sizeof(ry_buf), "%d", res_y > 0 ? res_y : 720);
  const char* cmd[] = {"osd-overlay",   id_buf,  "ass-events", ass_data.c_str(),
                       rx_buf,          ry_buf,  "0",          "no",
                       "no",            nullptr};
  g_procs.command(ctx_, cmd);
}

std::string NativeMpvHost::GetPropString(const char* name) {
  if (!ctx_ || !g_procs.get_property_string) return "";
  char* p = g_procs.get_property_string(ctx_, name);
  if (!p) return "";
  std::string out(p);
  g_procs.free(p);
  return out;
}

bool NativeMpvHost::GetPropDouble(const char* name, double* out) {
  if (!ctx_ || !g_procs.get_property) return false;
  return g_procs.get_property(ctx_, name, kMpvFormatDouble, out) >= 0;
}

bool NativeMpvHost::GetPropInt64(const char* name, int64_t* out) {
  if (!ctx_ || !g_procs.get_property) return false;
  return g_procs.get_property(ctx_, name, kMpvFormatInt64, out) >= 0;
}

bool NativeMpvHost::GetPropFlag(const char* name, bool* out) {
  if (!ctx_ || !g_procs.get_property) return false;
  int v = 0;
  if (g_procs.get_property(ctx_, name, kMpvFormatFlag, &v) < 0) return false;
  *out = (v != 0);
  return true;
}

flutter::EncodableMap NativeMpvHost::PollState() {
  std::lock_guard<std::mutex> lock(mpv_mu_);
  flutter::EncodableMap m;
  if (!ctx_) {
    m[flutter::EncodableValue("running")] = flutter::EncodableValue(false);
    return m;
  }
  double dur = 0;
  double pos = -1;
  bool has_pos = GetPropDouble("time-pos", &pos);
  GetPropDouble("duration", &dur);
  bool paused = false;
  GetPropFlag("pause", &paused);
  double volume = 100;
  GetPropDouble("volume", &volume);
  bool muted = false;
  GetPropFlag("mute", &muted);
  bool idle = false;
  GetPropFlag("idle-active", &idle);
  bool eof = eof_reached_.load();
  bool eof_prop = false;
  if (GetPropFlag("eof-reached", &eof_prop) && eof_prop) eof = true;
  int64_t w = 0, h = 0;
  GetPropInt64("width", &w);
  GetPropInt64("height", &h);
  double cache_speed = 0;
  GetPropDouble("cache-speed", &cache_speed);
  double cache_dur = 0;
  GetPropDouble("demuxer-cache-duration", &cache_dur);
  double speed = 1.0;
  GetPropDouble("speed", &speed);

  m[flutter::EncodableValue("running")] =
      flutter::EncodableValue(playback_started_.load());
  m[flutter::EncodableValue("hasPosition")] = flutter::EncodableValue(has_pos);
  m[flutter::EncodableValue("position")] =
      flutter::EncodableValue(has_pos ? pos : 0.0);
  m[flutter::EncodableValue("duration")] = flutter::EncodableValue(dur);
  m[flutter::EncodableValue("paused")] = flutter::EncodableValue(paused);
  m[flutter::EncodableValue("volume")] = flutter::EncodableValue(volume);
  m[flutter::EncodableValue("muted")] = flutter::EncodableValue(muted);
  m[flutter::EncodableValue("idle")] = flutter::EncodableValue(idle);
  m[flutter::EncodableValue("eof")] = flutter::EncodableValue(eof);
  m[flutter::EncodableValue("width")] =
      flutter::EncodableValue(static_cast<int>(w));
  m[flutter::EncodableValue("height")] =
      flutter::EncodableValue(static_cast<int>(h));
  m[flutter::EncodableValue("cacheSpeed")] =
      flutter::EncodableValue(cache_speed);
  m[flutter::EncodableValue("cacheDuration")] =
      flutter::EncodableValue(cache_dur);
  m[flutter::EncodableValue("speed")] = flutter::EncodableValue(speed);
  return m;
}

flutter::EncodableMap NativeMpvHost::ReadProps() {
  std::lock_guard<std::mutex> lock(mpv_mu_);
  std::string backend;
  {
    std::lock_guard<std::mutex> ml(meta_mu_);
    backend = render_backend_;
  }
  flutter::EncodableMap m;
  m[flutter::EncodableValue("renderBackend")] =
      flutter::EncodableValue(backend);
  if (!ctx_ || !playback_started_.load()) {
    m[flutter::EncodableValue("running")] = flutter::EncodableValue(false);
    return m;
  }

  int64_t w = 0, h = 0, dropped = 0, cache_secs = 0;
  GetPropInt64("width", &w);
  GetPropInt64("height", &h);
  GetPropInt64("frame-drop-count", &dropped);
  GetPropInt64("cache-secs", &cache_secs);
  double speed = 1.0, cache_speed = 0.0, cache_dur = 0.0;
  GetPropDouble("speed", &speed);
  GetPropDouble("cache-speed", &cache_speed);
  GetPropDouble("demuxer-cache-duration", &cache_dur);

  m[flutter::EncodableValue("running")] = flutter::EncodableValue(true);
  m[flutter::EncodableValue("hwdecCurrent")] =
      flutter::EncodableValue(GetPropString("hwdec-current"));
  m[flutter::EncodableValue("width")] =
      flutter::EncodableValue(static_cast<int>(w));
  m[flutter::EncodableValue("height")] =
      flutter::EncodableValue(static_cast<int>(h));
  m[flutter::EncodableValue("renderWidth")] =
      flutter::EncodableValue(viewport_w_);
  m[flutter::EncodableValue("renderHeight")] =
      flutter::EncodableValue(viewport_h_);
  m[flutter::EncodableValue("format")] =
      flutter::EncodableValue(GetPropString("video-format"));
  m[flutter::EncodableValue("dropped")] =
      flutter::EncodableValue(static_cast<int>(dropped));
  m[flutter::EncodableValue("cacheSecs")] =
      flutter::EncodableValue(static_cast<int>(cache_secs));
  m[flutter::EncodableValue("speed")] = flutter::EncodableValue(speed);
  m[flutter::EncodableValue("cacheSpeed")] =
      flutter::EncodableValue(cache_speed);
  m[flutter::EncodableValue("cacheDuration")] =
      flutter::EncodableValue(cache_dur);
  return m;
}

flutter::EncodableMap NativeMpvHost::GetTracks() {
  std::lock_guard<std::mutex> lock(mpv_mu_);
  flutter::EncodableMap m;
  if (!ctx_) {
    m[flutter::EncodableValue("trackListJson")] = flutter::EncodableValue("[]");
    m[flutter::EncodableValue("sid")] = flutter::EncodableValue("no");
    m[flutter::EncodableValue("aid")] = flutter::EncodableValue("");
    return m;
  }
  std::string track_json = GetPropString("track-list");
  if (track_json.empty()) track_json = "[]";
  m[flutter::EncodableValue("trackListJson")] =
      flutter::EncodableValue(track_json);
  m[flutter::EncodableValue("sid")] =
      flutter::EncodableValue(GetPropString("sid"));
  m[flutter::EncodableValue("aid")] =
      flutter::EncodableValue(GetPropString("aid"));
  return m;
}

flutter::EncodableMap NativeMpvHost::CaptureFrame() {
  std::lock_guard<std::mutex> lock(mpv_mu_);
  flutter::EncodableMap out;
  if (!ctx_ || !playback_started_.load() || !g_procs.command_node ||
      !g_procs.free_node_contents) {
    return out;
  }

  auto tryCapture = [&](const char* target) -> bool {
    MpvNode items[2]{};
    items[0].format = kMpvFormatString;
    items[0].u.string = const_cast<char*>("screenshot-raw");
    items[1].format = kMpvFormatString;
    items[1].u.string = const_cast<char*>(target);
    MpvNodeList list{};
    list.num = 2;
    list.values = items;
    list.keys = nullptr;
    MpvNode args{};
    args.format = kMpvFormatNodeArray;
    args.u.list = &list;

    MpvNode res{};
    if (g_procs.command_node(ctx_, &args, &res) < 0) {
      return false;
    }

    bool captured = false;
    if (res.format == kMpvFormatNodeMap && res.u.list != nullptr) {
      int64_t w = 0, h = 0, stride = 0;
      std::string fmt;
      const MpvByteArray* ba = nullptr;
      for (int i = 0; i < res.u.list->num; ++i) {
        const char* k = res.u.list->keys ? res.u.list->keys[i] : nullptr;
        if (!k) continue;
        const MpvNode& v = res.u.list->values[i];
        if (std::strcmp(k, "w") == 0 && v.format == kMpvFormatInt64) {
          w = v.u.int64;
        } else if (std::strcmp(k, "h") == 0 && v.format == kMpvFormatInt64) {
          h = v.u.int64;
        } else if (std::strcmp(k, "stride") == 0 && v.format == kMpvFormatInt64) {
          stride = v.u.int64;
        } else if (std::strcmp(k, "format") == 0 &&
                   v.format == kMpvFormatString && v.u.string) {
          fmt = v.u.string;
        } else if (std::strcmp(k, "data") == 0 &&
                   v.format == kMpvFormatByteArray) {
          ba = v.u.ba;
        }
      }

      if (w > 0 && h > 0 && w <= 7680 && h <= 4320 && stride >= w * 4 && ba &&
          ba->data &&
          ba->size >= static_cast<size_t>(stride) * static_cast<size_t>(h)) {
        const size_t row_bytes = static_cast<size_t>(w) * 4;
        std::vector<uint8_t> pixels(row_bytes * static_cast<size_t>(h));
        const auto* src = static_cast<const uint8_t*>(ba->data);
        const bool is_rgba = (fmt == "rgba" || fmt == "rgb0");
        const bool opaque = (fmt == "bgr0" || fmt == "rgb0" || fmt.empty());
        for (int64_t y = 0; y < h; ++y) {
          const uint8_t* row =
              src + static_cast<size_t>(y) * static_cast<size_t>(stride);
          uint8_t* dst = pixels.data() + static_cast<size_t>(y) * row_bytes;
          if (!is_rgba && !opaque) {
            std::memcpy(dst, row, row_bytes);
          } else if (!is_rgba) {
            std::memcpy(dst, row, row_bytes);
            for (size_t x = 3; x < row_bytes; x += 4) dst[x] = 0xFF;
          } else {
            for (size_t x = 0; x < row_bytes; x += 4) {
              dst[x] = row[x + 2];
              dst[x + 1] = row[x + 1];
              dst[x + 2] = row[x];
              dst[x + 3] = opaque ? 0xFF : row[x + 3];
            }
          }
        }
        out[flutter::EncodableValue("w")] =
            flutter::EncodableValue(static_cast<int>(w));
        out[flutter::EncodableValue("h")] =
            flutter::EncodableValue(static_cast<int>(h));
        out[flutter::EncodableValue("bytes")] =
            flutter::EncodableValue(std::move(pixels));
        captured = true;
      }
    }

    g_procs.free_node_contents(&res);
    return captured;
  };

  if (!tryCapture("window")) {
    tryCapture("video");
  }
  return out;
}

void NativeMpvHost::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());

  if (method == "setViewport") {
    int x = 0, y = 0, w = 1, h = 1;
    bool visible = false;
    bool hide_cursor = false;
    GetIntArg(args, "x", &x);
    GetIntArg(args, "y", &y);
    GetIntArg(args, "w", &w);
    GetIntArg(args, "h", &h);
    GetBoolArg(args, "visible", &visible);
    GetBoolArg(args, "hideCursor", &hide_cursor);
    SetViewport(x, y, w, h, visible, hide_cursor);
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (method == "open") {
    std::string url, title, hwdec_mode = "auto";
    double start = 0.0;
    int cache_secs = 120;
    GetStringArg(args, "url", &url);
    GetStringArg(args, "title", &title);
    GetStringArg(args, "hwdecMode", &hwdec_mode);
    GetDoubleArg(args, "start", &start);
    GetIntArg(args, "cacheSecs", &cache_secs);
    std::vector<std::string> hdrs;
    if (args) {
      auto it = args->find(flutter::EncodableValue("headers"));
      if (it != args->end()) {
        if (const auto* list =
                std::get_if<flutter::EncodableList>(&it->second)) {
          for (const auto& item : *list) {
            if (const auto* s = std::get_if<std::string>(&item)) {
              hdrs.push_back(*s);
            }
          }
        }
      }
    }
    bool ok = OpenMedia(url, title, start, cache_secs, hdrs, hwdec_mode);
    result->Success(flutter::EncodableValue(ok));
    return;
  }
  if (method == "stop") {
    StopPlayback();
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (method == "pause") {
    SetPaused(true);
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (method == "play") {
    SetPaused(false);
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (method == "playOrPause") {
    TogglePause();
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (method == "seekAbsolute") {
    double s = 0.0;
    GetDoubleArg(args, "seconds", &s);
    SeekAbsolute(s);
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (method == "setVolume") {
    double v = 100.0;
    GetDoubleArg(args, "volume", &v);
    SetVolume(v);
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (method == "setMute") {
    bool muted = false;
    GetBoolArg(args, "muted", &muted);
    SetMute(muted);
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (method == "setRate") {
    double r = 1.0;
    GetDoubleArg(args, "rate", &r);
    SetRate(r);
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (method == "setHwdecMode") {
    std::string mode = "auto";
    GetStringArg(args, "mode", &mode);
    ApplyHwdec(mode);
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (method == "setSubTrack") {
    std::string id = "no";
    GetStringArg(args, "id", &id);
    SetSubTrack(id);
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (method == "setAudioTrack") {
    std::string id;
    GetStringArg(args, "id", &id);
    SetAudioTrack(id);
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (method == "addExternalSubtitle") {
    std::string path;
    GetStringArg(args, "path", &path);
    AddExternalSubtitle(path);
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (method == "setOsdOverlay") {
    int id = 1, rx = 1280, ry = 720;
    std::string data;
    GetIntArg(args, "id", &id);
    GetStringArg(args, "data", &data);
    GetIntArg(args, "resX", &rx);
    GetIntArg(args, "resY", &ry);
    SetOsdOverlay(id, data, rx, ry);
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (method == "pollState") {
    result->Success(flutter::EncodableValue(PollState()));
    return;
  }
  if (method == "readProps") {
    result->Success(flutter::EncodableValue(ReadProps()));
    return;
  }
  if (method == "getTracks") {
    result->Success(flutter::EncodableValue(GetTracks()));
    return;
  }
  if (method == "captureFrame") {
    result->Success(flutter::EncodableValue(CaptureFrame()));
    return;
  }
  if (method == "disposeEngine") {
    SetViewport(0, 0, 1, 1, false, false);
    DestroyMpvInstance();
    result->Success(flutter::EncodableValue(true));
    return;
  }
  result->NotImplemented();
}

std::unique_ptr<NativeMpvHost> RegisterNativeMpvHost(
    flutter::BinaryMessenger* messenger,
    HWND parent_hwnd,
    HWND flutter_hwnd) {
  auto host = std::make_unique<NativeMpvHost>(parent_hwnd, flutter_hwnd);
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "kimbox/native_mpv",
          &flutter::StandardMethodCodec::GetInstance());
  NativeMpvHost* raw = host.get();
  channel->SetMethodCallHandler(
      [raw](const flutter::MethodCall<flutter::EncodableValue>& call,
            std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                result) { raw->HandleMethodCall(call, std::move(result)); });
  host->AttachChannel(std::move(channel));
  return host;
}
