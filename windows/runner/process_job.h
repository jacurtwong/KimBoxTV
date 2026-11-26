#ifndef RUNNER_PROCESS_JOB_H_
#define RUNNER_PROCESS_JOB_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterProcessJobChannel(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_PROCESS_JOB_H_
