#ifndef RUNNER_RENDER_PROBE_CHANNEL_H_
#define RUNNER_RENDER_PROBE_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

void InstallRenderProbe();
void UninstallRenderProbe();

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterRenderProbeChannel(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_RENDER_PROBE_CHANNEL_H_
