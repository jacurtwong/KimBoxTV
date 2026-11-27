#ifndef RUNNER_NATIVE_MPV_HOST_H_
#define RUNNER_NATIVE_MPV_HOST_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

struct mpv_handle;

class NativeMpvHost {
 public:
  NativeMpvHost(HWND parent_hwnd, HWND flutter_hwnd);
  ~NativeMpvHost();

  void AttachChannel(
      std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel);
  void DetachAndDispose();

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  static constexpr UINT kWmMpvBackend = WM_APP + 0x41;
  static constexpr UINT kWmMpvEnded = WM_APP + 0x42;
  static constexpr UINT_PTR kTapTimerId = 0x5101;

  bool EnsureWindowCreated();
  bool EnsureMpvLoaded();
  bool EnsureMpvCreated();
  void DestroyMpvInstance();

  void SetViewport(int x, int y, int w, int h, bool visible, bool hide_cursor);
  bool OpenMedia(const std::string& url,
                 const std::string& title,
                 double start_sec,
                 int cache_secs,
                 const std::vector<std::string>& headers,
                 const std::string& hwdec_mode);
  void ApplyHwdec(const std::string& mode);
  void StopPlayback();
  void SetPaused(bool paused);
  void TogglePause();
  void SeekAbsolute(double seconds);
  void SetVolume(double volume);
  void SetMute(bool muted);
  void SetRate(double rate);
  void SetSubTrack(const std::string& id);
  void SetAudioTrack(const std::string& id);
  void AddExternalSubtitle(const std::string& path);
  void SetOsdOverlay(int id, const std::string& ass_data, int res_x, int res_y);

  flutter::EncodableMap PollState();
  flutter::EncodableMap ReadProps();
  flutter::EncodableMap GetTracks();
  flutter::EncodableMap CaptureFrame();

  void EventLoop();
  std::string GetPropString(const char* name);
  bool GetPropDouble(const char* name, double* out);
  bool GetPropInt64(const char* name, int64_t* out);
  bool GetPropFlag(const char* name, bool* out);

  static LRESULT CALLBACK HostWndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);
  static LRESULT CALLBACK SurfaceWndProc(HWND hwnd,
                                         UINT msg,
                                         WPARAM wp,
                                         LPARAM lp);
  LRESULT HandleHostMessage(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);

  HWND parent_hwnd_ = nullptr;
  HWND flutter_hwnd_ = nullptr;
  HWND host_hwnd_ = nullptr;
  HWND mpv_hwnd_ = nullptr;
  HBRUSH black_brush_ = nullptr;

  HMODULE libmpv_ = nullptr;
  mpv_handle* ctx_ = nullptr;
  std::mutex mpv_mu_;

  std::thread event_thread_;
  std::atomic<bool> stop_events_{false};
  std::atomic<bool> playback_started_{false};
  std::atomic<bool> eof_reached_{false};

  std::mutex meta_mu_;
  std::string render_backend_ = "native_gpu";
  std::string hwdec_mode_ = "auto";
  int viewport_w_ = 0;
  int viewport_h_ = 0;
  bool visible_ = false;
  bool hide_cursor_ = false;
  POINT last_mouse_pt_{-1, -1};
  ULONGLONG last_move_tick_ = 0;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

std::unique_ptr<NativeMpvHost> RegisterNativeMpvHost(
    flutter::BinaryMessenger* messenger,
    HWND parent_hwnd,
    HWND flutter_hwnd);

#endif  // RUNNER_NATIVE_MPV_HOST_H_
