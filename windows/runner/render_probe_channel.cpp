#include "render_probe_channel.h"

#include <flutter/standard_method_codec.h>

#include <deque>
#include <iostream>
#include <mutex>
#include <streambuf>
#include <string>
#include <vector>

namespace {

struct ProbeSnapshot {
  std::string backend = "unknown";  // "unknown" | "hw_angle" | "sw_fallback"
  std::string angle_failure;
  std::deque<std::string> logs;
};

std::string Trim(const std::string& s) {
  const auto first = s.find_first_not_of(" \t\r\n");
  if (first == std::string::npos) return "";
  const auto last = s.find_last_not_of(" \t\r\n");
  return s.substr(first, last - first + 1);
}

class RenderProbeStreambuf final : public std::streambuf {
 public:
  explicit RenderProbeStreambuf(std::streambuf* original)
      : original_(original) {}

  ProbeSnapshot Snapshot() const {
    std::lock_guard<std::mutex> lock(mu_);
    return state_;
  }

  void ResetBackend() {
    std::lock_guard<std::mutex> lock(mu_);
    state_.backend = "unknown";
    state_.angle_failure.clear();
  }

 protected:
  int_type overflow(int_type ch) override {
    if (ch == traits_type::eof()) {
      return traits_type::not_eof(ch);
    }
    const char c = traits_type::to_char_type(ch);
    if (original_ != nullptr) {
      original_->sputc(c);
    }
    std::lock_guard<std::mutex> lock(mu_);
    if (c == '\n') {
      HandleLineLocked(line_buf_);
      line_buf_.clear();
    } else if (c != '\r') {
      if (line_buf_.size() < 2048) {
        line_buf_.push_back(c);
      }
    }
    return traits_type::not_eof(ch);
  }

  std::streamsize xsputn(const char* s, std::streamsize count) override {
    if (original_ != nullptr && s != nullptr && count > 0) {
      original_->sputn(s, count);
    }
    if (s == nullptr || count <= 0) {
      return 0;
    }
    std::lock_guard<std::mutex> lock(mu_);
    for (std::streamsize i = 0; i < count; ++i) {
      const char c = s[i];
      if (c == '\n') {
        HandleLineLocked(line_buf_);
        line_buf_.clear();
      } else if (c != '\r') {
        if (line_buf_.size() < 2048) {
          line_buf_.push_back(c);
        }
      }
    }
    return count;
  }

  int sync() override {
    if (original_ != nullptr) {
      original_->pubsync();
    }
    return 0;
  }

 private:
  void HandleLineLocked(const std::string& raw) {
    const std::string line = Trim(raw);
    if (line.empty()) return;
    if (line.find("media_kit:") == std::string::npos) {
      return;
    }
    if (state_.logs.size() >= 20) {
      state_.logs.pop_front();
    }
    state_.logs.push_back(line);

    if (line.find("Using H/W rendering") != std::string::npos) {
      state_.backend = "hw_angle";
    } else if (line.find("Using S/W rendering") != std::string::npos) {
      state_.backend = "sw_fallback";
    } else {
      constexpr const char* kFailPrefix = "ANGLESurfaceManager: Failure:";
      const auto pos = line.find(kFailPrefix);
      if (pos != std::string::npos) {
        state_.angle_failure =
            Trim(line.substr(pos + std::char_traits<char>::length(kFailPrefix)));
      }
    }
  }

  std::streambuf* original_ = nullptr;
  mutable std::mutex mu_;
  std::string line_buf_;
  ProbeSnapshot state_;
};

std::mutex& InstallMutex() {
  static std::mutex m;
  return m;
}

std::streambuf* g_original_cout_buf = nullptr;
std::unique_ptr<RenderProbeStreambuf> g_probe_buf;

}  // namespace

void InstallRenderProbe() {
  std::lock_guard<std::mutex> lock(InstallMutex());
  if (g_probe_buf) return;
  g_original_cout_buf = std::cout.rdbuf();
  g_probe_buf = std::make_unique<RenderProbeStreambuf>(g_original_cout_buf);
  std::cout.rdbuf(g_probe_buf.get());
}

void UninstallRenderProbe() {
  std::lock_guard<std::mutex> lock(InstallMutex());
  if (!g_probe_buf) return;
  std::cout.rdbuf(g_original_cout_buf);
  g_original_cout_buf = nullptr;
  g_probe_buf.reset();
}

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterRenderProbeChannel(flutter::BinaryMessenger* messenger) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "kimbox/render_probe",
          &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "getStatus") {
          ProbeSnapshot snap;
          {
            std::lock_guard<std::mutex> lock(InstallMutex());
            if (g_probe_buf) {
              snap = g_probe_buf->Snapshot();
            }
          }
          flutter::EncodableList logs_list;
          for (const auto& entry : snap.logs) {
            logs_list.push_back(flutter::EncodableValue(entry));
          }
          flutter::EncodableMap map;
          map[flutter::EncodableValue("backend")] =
              flutter::EncodableValue(snap.backend);
          map[flutter::EncodableValue("angleFailure")] =
              flutter::EncodableValue(snap.angle_failure);
          map[flutter::EncodableValue("logs")] =
              flutter::EncodableValue(logs_list);
          result->Success(flutter::EncodableValue(map));
          return;
        }
        if (call.method_name() == "reset") {
          std::lock_guard<std::mutex> lock(InstallMutex());
          if (g_probe_buf) {
            g_probe_buf->ResetBackend();
          }
          result->Success();
          return;
        }
        result->NotImplemented();
      });
  return channel;
}
