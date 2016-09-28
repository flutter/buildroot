// Copyright 2014 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// This file contains the definitions of the system functions, which are
// declared in various header files in mojo/public/c/system.

#include "mojo/edk/embedder/embedder_internal.h"
#include "mojo/edk/system/core.h"
#include "mojo/public/c/system/buffer.h"
#include "mojo/public/c/system/data_pipe.h"
#include "mojo/public/c/system/handle.h"
#include "mojo/public/c/system/message_pipe.h"
#include "mojo/public/c/system/time.h"
#include "mojo/public/c/system/wait.h"

using mojo::embedder::internal::g_core;
using mojo::system::MakeUserPointer;

extern "C" {

MojoTimeTicks MojoGetTimeTicksNow() {
  return g_core->GetTimeTicksNow();
}

MojoResult MojoClose(MojoHandle handle) {
  return g_core->Close(handle);
}

MojoResult MojoGetRights(MojoHandle handle, MojoHandleRights* rights) {
  return g_core->GetRights(handle, MakeUserPointer(rights));
}

MojoResult MojoReplaceHandleWithReducedRights(MojoHandle handle,
                                              MojoHandleRights rights_to_remove,
                                              MojoHandle* replacement_handle) {
  return g_core->ReplaceHandleWithReducedRights(
      handle, rights_to_remove, MakeUserPointer(replacement_handle));
}

MojoResult MojoDuplicateHandleWithReducedRights(
    MojoHandle handle,
    MojoHandleRights rights_to_remove,
    MojoHandle* new_handle) {
  return g_core->DuplicateHandleWithReducedRights(handle, rights_to_remove,
                                                  MakeUserPointer(new_handle));
}

MojoResult MojoDuplicateHandle(MojoHandle handle, MojoHandle* new_handle) {
  return g_core->DuplicateHandleWithReducedRights(
      handle, MOJO_HANDLE_RIGHT_NONE, MakeUserPointer(new_handle));
}

MojoResult MojoWait(MojoHandle handle,
                    MojoHandleSignals signals,
                    MojoDeadline deadline,
                    MojoHandleSignalsState* signals_state) {
  return g_core->Wait(handle, signals, deadline,
                      MakeUserPointer(signals_state));
}

MojoResult MojoWaitMany(const MojoHandle* handles,
                        const MojoHandleSignals* signals,
                        uint32_t num_handles,
                        MojoDeadline deadline,
                        uint32_t* result_index,
                        MojoHandleSignalsState* signals_states) {
  return g_core->WaitMany(MakeUserPointer(handles), MakeUserPointer(signals),
                          num_handles, deadline, MakeUserPointer(result_index),
                          MakeUserPointer(signals_states));
}

MojoResult MojoCreateMessagePipe(const MojoCreateMessagePipeOptions* options,
                                 MojoHandle* message_pipe_handle0,
                                 MojoHandle* message_pipe_handle1) {
  return g_core->CreateMessagePipe(MakeUserPointer(options),
                                   MakeUserPointer(message_pipe_handle0),
                                   MakeUserPointer(message_pipe_handle1));
}

MojoResult MojoWriteMessage(MojoHandle message_pipe_handle,
                            const void* bytes,
                            uint32_t num_bytes,
                            const MojoHandle* handles,
                            uint32_t num_handles,
                            MojoWriteMessageFlags flags) {
  return g_core->WriteMessage(message_pipe_handle, MakeUserPointer(bytes),
                              num_bytes, MakeUserPointer(handles), num_handles,
                              flags);
}

MojoResult MojoReadMessage(MojoHandle message_pipe_handle,
                           void* bytes,
                           uint32_t* num_bytes,
                           MojoHandle* handles,
                           uint32_t* num_handles,
                           MojoReadMessageFlags flags) {
  return g_core->ReadMessage(
      message_pipe_handle, MakeUserPointer(bytes), MakeUserPointer(num_bytes),
      MakeUserPointer(handles), MakeUserPointer(num_handles), flags);
}

MojoResult MojoCreateDataPipe(const MojoCreateDataPipeOptions* options,
                              MojoHandle* data_pipe_producer_handle,
                              MojoHandle* data_pipe_consumer_handle) {
  return g_core->CreateDataPipe(MakeUserPointer(options),
                                MakeUserPointer(data_pipe_producer_handle),
                                MakeUserPointer(data_pipe_consumer_handle));
}

MojoResult MojoSetDataPipeProducerOptions(
    MojoHandle data_pipe_producer_handle,
    const struct MojoDataPipeProducerOptions* options) {
  return g_core->SetDataPipeProducerOptions(data_pipe_producer_handle,
                                            MakeUserPointer(options));
}

MojoResult MojoGetDataPipeProducerOptions(
    MojoHandle data_pipe_producer_handle,
    struct MojoDataPipeProducerOptions* options,
    uint32_t options_num_bytes) {
  return g_core->GetDataPipeProducerOptions(
      data_pipe_producer_handle, MakeUserPointer(options), options_num_bytes);
}

MojoResult MojoWriteData(MojoHandle data_pipe_producer_handle,
                         const void* elements,
                         uint32_t* num_elements,
                         MojoWriteDataFlags flags) {
  return g_core->WriteData(data_pipe_producer_handle, MakeUserPointer(elements),
                           MakeUserPointer(num_elements), flags);
}

MojoResult MojoBeginWriteData(MojoHandle data_pipe_producer_handle,
                              void** buffer,
                              uint32_t* buffer_num_elements,
                              MojoWriteDataFlags flags) {
  return g_core->BeginWriteData(data_pipe_producer_handle,
                                MakeUserPointer(buffer),
                                MakeUserPointer(buffer_num_elements), flags);
}

MojoResult MojoEndWriteData(MojoHandle data_pipe_producer_handle,
                            uint32_t num_elements_written) {
  return g_core->EndWriteData(data_pipe_producer_handle, num_elements_written);
}

MojoResult MojoSetDataPipeConsumerOptions(
    MojoHandle data_pipe_consumer_handle,
    const struct MojoDataPipeConsumerOptions* options) {
  return g_core->SetDataPipeConsumerOptions(data_pipe_consumer_handle,
                                            MakeUserPointer(options));
}

MojoResult MojoGetDataPipeConsumerOptions(
    MojoHandle data_pipe_consumer_handle,
    struct MojoDataPipeConsumerOptions* options,
    uint32_t options_num_bytes) {
  return g_core->GetDataPipeConsumerOptions(
      data_pipe_consumer_handle, MakeUserPointer(options), options_num_bytes);
}

MojoResult MojoReadData(MojoHandle data_pipe_consumer_handle,
                        void* elements,
                        uint32_t* num_elements,
                        MojoReadDataFlags flags) {
  return g_core->ReadData(data_pipe_consumer_handle, MakeUserPointer(elements),
                          MakeUserPointer(num_elements), flags);
}

MojoResult MojoBeginReadData(MojoHandle data_pipe_consumer_handle,
                             const void** buffer,
                             uint32_t* buffer_num_elements,
                             MojoReadDataFlags flags) {
  return g_core->BeginReadData(data_pipe_consumer_handle,
                               MakeUserPointer(buffer),
                               MakeUserPointer(buffer_num_elements), flags);
}

MojoResult MojoEndReadData(MojoHandle data_pipe_consumer_handle,
                           uint32_t num_elements_read) {
  return g_core->EndReadData(data_pipe_consumer_handle, num_elements_read);
}

MojoResult MojoCreateSharedBuffer(
    const struct MojoCreateSharedBufferOptions* options,
    uint64_t num_bytes,
    MojoHandle* shared_buffer_handle) {
  return g_core->CreateSharedBuffer(MakeUserPointer(options), num_bytes,
                                    MakeUserPointer(shared_buffer_handle));
}

MojoResult MojoDuplicateBufferHandle(
    MojoHandle buffer_handle,
    const struct MojoDuplicateBufferHandleOptions* options,
    MojoHandle* new_buffer_handle) {
  return g_core->DuplicateBufferHandle(buffer_handle, MakeUserPointer(options),
                                       MakeUserPointer(new_buffer_handle));
}

MojoResult MojoGetBufferInformation(MojoHandle buffer_handle,
                                    struct MojoBufferInformation* info,
                                    uint32_t info_num_bytes) {
  return g_core->GetBufferInformation(buffer_handle, MakeUserPointer(info),
                                      info_num_bytes);
}

MojoResult MojoMapBuffer(MojoHandle buffer_handle,
                         uint64_t offset,
                         uint64_t num_bytes,
                         void** buffer,
                         MojoMapBufferFlags flags) {
  return g_core->MapBuffer(buffer_handle, offset, num_bytes,
                           MakeUserPointer(buffer), flags);
}

MojoResult MojoUnmapBuffer(void* buffer) {
  return g_core->UnmapBuffer(MakeUserPointer(buffer));
}

MojoResult MojoCreateWaitSet(const struct MojoCreateWaitSetOptions* options,
                             MojoHandle* handle) {
  return g_core->CreateWaitSet(MakeUserPointer(options),
                               MakeUserPointer(handle));
}

MojoResult MojoWaitSetAdd(MojoHandle wait_set_handle,
                          MojoHandle handle,
                          MojoHandleSignals signals,
                          uint64_t cookie,
                          const struct MojoWaitSetAddOptions* options) {
  return g_core->WaitSetAdd(wait_set_handle, handle, signals, cookie,
                            MakeUserPointer(options));
}

MojoResult MojoWaitSetRemove(MojoHandle wait_set_handle, uint64_t cookie) {
  return g_core->WaitSetRemove(wait_set_handle, cookie);
}

MojoResult MojoWaitSetWait(MojoHandle wait_set_handle,
                           MojoDeadline deadline,
                           uint32_t* num_results,
                           struct MojoWaitSetResult* results,
                           uint32_t* max_results) {
  return g_core->WaitSetWait(
      wait_set_handle, deadline, MakeUserPointer(num_results),
      MakeUserPointer(results), MakeUserPointer(max_results));
}

}  // extern "C"
