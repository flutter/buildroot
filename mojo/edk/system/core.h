// Copyright 2013 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef MOJO_EDK_SYSTEM_CORE_H_
#define MOJO_EDK_SYSTEM_CORE_H_

#include <stdint.h>

#include <functional>

#include "mojo/edk/system/entrypoint_class.h"
#include "mojo/edk/system/handle.h"
#include "mojo/edk/system/handle_table.h"
#include "mojo/edk/system/mapping_table.h"
#include "mojo/edk/system/memory.h"
#include "mojo/edk/util/mutex.h"
#include "mojo/edk/util/ref_ptr.h"
#include "mojo/edk/util/thread_annotations.h"
#include "mojo/public/c/system/buffer.h"
#include "mojo/public/c/system/data_pipe.h"
#include "mojo/public/c/system/handle.h"
#include "mojo/public/c/system/message_pipe.h"
#include "mojo/public/c/system/result.h"
#include "mojo/public/c/system/time.h"
#include "mojo/public/c/system/wait_set.h"
#include "mojo/public/cpp/system/macros.h"

namespace mojo {

namespace embedder {
class PlatformSupport;
}

namespace system {

class Dispatcher;
struct HandleSignalsState;

// |Core| is an object that implements the Mojo system calls. All public methods
// are thread-safe.
//
// Convention: |MojoHandle|s are referred to as |handle| or |foo_handle|,
// whereas |Handle|s are just |h|.
class Core {
 public:
  // ---------------------------------------------------------------------------

  // These methods are only to be used by via the embedder API (and internally):

  // |*platform_support| must outlive this object.
  explicit Core(embedder::PlatformSupport* platform_support);
  virtual ~Core();

  // Adds |handle| (which must have a dispatcher) to the handle table, returning
  // the handle value for it. Returns |MOJO_HANDLE_INVALID| on failure, namely
  // if the handle table is full.
  MojoHandle AddHandle(Handle&& h);

  // Gets the handle for the given handle value. On success, returns
  // |MOJO_RESULT_OK| (and sets |*h|). On failure, returns an appropriate result
  // (and leaves |*h| alone), namely |MOJO_RESULT_INVALID_ARGUMENT| if the
  // handle value is invalid or |MOJO_RESULT_BUSY| if the handle is marked as
  // busy.
  MojoResult GetHandle(MojoHandle handle, Handle* h);

  // Like |GetHandle()|, but on success also removes the handle from the
  // handle table.
  MojoResult GetAndRemoveHandle(MojoHandle handle, Handle* h);

  // Gets the dispatcher for the given handle value, which must have (all of)
  // the rights in |required_handle_rights|.
  //
  // On success, returns |MOJO_RESULT_OK| and sets |*dispatcher| appropriately.
  // On failure, returns:
  //   - |MOJO_RESULT_INVALID_ARGUMENT| if there's no handle for the given
  //     handle value (or the handle value was |MOJO_HANDLE_INVALID|),
  //   - |MOJO_RESULT_BUSY| if the handle is marked as busy,
  //   - |MOJO_RESULT_PERMISSION_DENIED| if the handle does not have the
  //     required rights *and* the dispatcher supports the specified
  //     |entrypoint_class|, or
  //   - |MOJO_RESULT_INVALID_ARGUMENT| if the handle does not have the required
  //     rights *but* the dispatcher does not support |entrypoint_class|.
  // (Warning: if the handle has the required rights, then its dispatcher will
  // be returned even if the dispatcher does not support |entrypoint_class|.)
  MojoResult GetDispatcherAndCheckRights(
      MojoHandle handle_value,
      MojoHandleRights required_handle_rights,
      EntrypointClass entrypoint_class,
      util::RefPtr<Dispatcher>* dispatcher);

  // Watches on the given handle for the given signals, calling |callback| when
  // a signal is satisfied or when all signals become unsatisfiable. |callback|
  // must satisfy stringent requirements -- see |Awakable::Awake()| in
  // awakable.h. In particular, it must not call any Mojo system functions.
  MojoResult AsyncWait(MojoHandle handle,
                       MojoHandleSignals signals,
                       const std::function<void(MojoResult)>& callback);

  embedder::PlatformSupport* platform_support() const {
    return platform_support_;
  }

  // ---------------------------------------------------------------------------

  // The following methods are essentially implementations of the Mojo Core
  // functions of the Mojo API, with the C interface translated to C++ by
  // "mojo/edk/embedder/entrypoints.cc". The best way to understand the contract
  // of these methods is to look at the header files defining the corresponding
  // API functions, referenced below.

  // This method corresponds to the API function defined in
  // "mojo/public/c/system/time.h":

  MojoTimeTicks GetTimeTicksNow();

  // This method corresponds to the API function defined in
  // "mojo/public/c/system/handle.h":
  MojoResult Close(MojoHandle handle);
  MojoResult GetRights(MojoHandle handle, UserPointer<MojoHandleRights> rights);
  MojoResult ReplaceHandleWithReducedRights(
      MojoHandle handle,
      MojoHandleRights rights_to_remove,
      UserPointer<MojoHandle> replacement_handle);
  MojoResult DuplicateHandleWithReducedRights(
      MojoHandle handle,
      MojoHandleRights rights_to_remove,
      UserPointer<MojoHandle> new_handle);

  // These methods correspond to the API functions defined in
  // "mojo/public/c/system/wait.h":
  MojoResult Wait(MojoHandle handle,
                  MojoHandleSignals signals,
                  MojoDeadline deadline,
                  UserPointer<MojoHandleSignalsState> signals_state);
  MojoResult WaitMany(UserPointer<const MojoHandle> handles,
                      UserPointer<const MojoHandleSignals> signals,
                      uint32_t num_handles,
                      MojoDeadline deadline,
                      UserPointer<uint32_t> result_index,
                      UserPointer<MojoHandleSignalsState> signals_states);

  // These methods correspond to the API functions defined in
  // "mojo/public/c/system/message_pipe.h":
  MojoResult CreateMessagePipe(
      UserPointer<const MojoCreateMessagePipeOptions> options,
      UserPointer<MojoHandle> message_pipe_handle0,
      UserPointer<MojoHandle> message_pipe_handle1);
  MojoResult WriteMessage(MojoHandle message_pipe_handle,
                          UserPointer<const void> bytes,
                          uint32_t num_bytes,
                          UserPointer<const MojoHandle> handles,
                          uint32_t num_handles,
                          MojoWriteMessageFlags flags);
  MojoResult ReadMessage(MojoHandle message_pipe_handle,
                         UserPointer<void> bytes,
                         UserPointer<uint32_t> num_bytes,
                         UserPointer<MojoHandle> handles,
                         UserPointer<uint32_t> num_handles,
                         MojoReadMessageFlags flags);

  // These methods correspond to the API functions defined in
  // "mojo/public/c/system/data_pipe.h":
  MojoResult CreateDataPipe(
      UserPointer<const MojoCreateDataPipeOptions> options,
      UserPointer<MojoHandle> data_pipe_producer_handle,
      UserPointer<MojoHandle> data_pipe_consumer_handle);
  MojoResult SetDataPipeProducerOptions(
      MojoHandle data_pipe_producer_handle,
      UserPointer<const MojoDataPipeProducerOptions> options);
  MojoResult GetDataPipeProducerOptions(
      MojoHandle data_pipe_producer_handle,
      UserPointer<MojoDataPipeProducerOptions> options,
      uint32_t options_num_bytes);
  MojoResult WriteData(MojoHandle data_pipe_producer_handle,
                       UserPointer<const void> elements,
                       UserPointer<uint32_t> num_bytes,
                       MojoWriteDataFlags flags);
  MojoResult BeginWriteData(MojoHandle data_pipe_producer_handle,
                            UserPointer<void*> buffer,
                            UserPointer<uint32_t> buffer_num_bytes,
                            MojoWriteDataFlags flags);
  MojoResult EndWriteData(MojoHandle data_pipe_producer_handle,
                          uint32_t num_bytes_written);
  MojoResult SetDataPipeConsumerOptions(
      MojoHandle data_pipe_consumer_handle,
      UserPointer<const MojoDataPipeConsumerOptions> options);
  MojoResult GetDataPipeConsumerOptions(
      MojoHandle data_pipe_consumer_handle,
      UserPointer<MojoDataPipeConsumerOptions> options,
      uint32_t options_num_bytes);
  MojoResult ReadData(MojoHandle data_pipe_consumer_handle,
                      UserPointer<void> elements,
                      UserPointer<uint32_t> num_bytes,
                      MojoReadDataFlags flags);
  MojoResult BeginReadData(MojoHandle data_pipe_consumer_handle,
                           UserPointer<const void*> buffer,
                           UserPointer<uint32_t> buffer_num_bytes,
                           MojoReadDataFlags flags);
  MojoResult EndReadData(MojoHandle data_pipe_consumer_handle,
                         uint32_t num_bytes_read);

  // These methods correspond to the API functions defined in
  // "mojo/public/c/system/buffer.h":
  MojoResult CreateSharedBuffer(
      UserPointer<const MojoCreateSharedBufferOptions> options,
      uint64_t num_bytes,
      UserPointer<MojoHandle> shared_buffer_handle);
  MojoResult DuplicateBufferHandle(
      MojoHandle buffer_handle,
      UserPointer<const MojoDuplicateBufferHandleOptions> options,
      UserPointer<MojoHandle> new_buffer_handle);
  MojoResult GetBufferInformation(MojoHandle buffer_handle,
                                  UserPointer<MojoBufferInformation> info,
                                  uint32_t info_num_bytes);
  MojoResult MapBuffer(MojoHandle buffer_handle,
                       uint64_t offset,
                       uint64_t num_bytes,
                       UserPointer<void*> buffer,
                       MojoMapBufferFlags flags);
  MojoResult UnmapBuffer(UserPointer<void> buffer);

  // These methods correspond to the API functions defined in
  // "mojo/public/c/system/wait_set.h":
  MojoResult CreateWaitSet(UserPointer<const MojoCreateWaitSetOptions> options,
                           UserPointer<MojoHandle> wait_set_handle);
  MojoResult WaitSetAdd(MojoHandle wait_set_handle,
                        MojoHandle handle,
                        MojoHandleSignals signals,
                        uint64_t cookie,
                        UserPointer<const MojoWaitSetAddOptions> options);
  MojoResult WaitSetRemove(MojoHandle wait_set_handle, uint64_t cookie);
  MojoResult WaitSetWait(MojoHandle wait_set_handle,
                         MojoDeadline deadline,
                         UserPointer<uint32_t> num_results,
                         UserPointer<MojoWaitSetResult> results,
                         UserPointer<uint32_t> max_results);

 private:
  friend bool internal::ShutdownCheckNoLeaks(Core*);

  // Internal implementation of |Wait()| and |WaitMany()|; doesn't do basic
  // validation of arguments. |*result_index| is only set if the result (whether
  // success or failure) applies to a specific handle, so its value should be
  // preinitialized to |static_cast<uint32_t>(-1)|.
  MojoResult WaitManyInternal(const MojoHandle* handles,
                              const MojoHandleSignals* signals,
                              uint32_t num_handles,
                              MojoDeadline deadline,
                              uint64_t* result_index,
                              HandleSignalsState* signals_states);

  embedder::PlatformSupport* const platform_support_;

  // TODO(vtl): |handle_table_mutex_| should be a reader-writer lock (if only we
  // had them).
  util::Mutex handle_table_mutex_;
  HandleTable handle_table_ MOJO_GUARDED_BY(handle_table_mutex_);

  util::Mutex mapping_table_mutex_;
  MappingTable mapping_table_ MOJO_GUARDED_BY(mapping_table_mutex_);

  MOJO_DISALLOW_COPY_AND_ASSIGN(Core);
};

}  // namespace system
}  // namespace mojo

#endif  // MOJO_EDK_SYSTEM_CORE_H_
