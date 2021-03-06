/*
 *
 * Copyright 2015, Google Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 *     * Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above
 * copyright notice, this list of conditions and the following disclaimer
 * in the documentation and/or other materials provided with the
 * distribution.
 *     * Neither the name of Google Inc. nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */

#include "test/cpp/interop/client_helper.h"

#include <fstream>
#include <memory>
#include <sstream>

#include <unistd.h>

#include <grpc/grpc.h>
#include <grpc/support/log.h>
#include <gflags/gflags.h>
#include <grpc++/channel_arguments.h>
#include <grpc++/channel_interface.h>
#include <grpc++/create_channel.h>
#include <grpc++/credentials.h>
#include <grpc++/stream.h>
#include "test/cpp/util/create_test_channel.h"

DECLARE_bool(enable_ssl);
DECLARE_bool(use_prod_roots);
DECLARE_int32(server_port);
DECLARE_string(server_host);
DECLARE_string(server_host_override);
DECLARE_string(test_case);
DECLARE_string(default_service_account);
DECLARE_string(service_account_key_file);
DECLARE_string(oauth_scope);

namespace grpc {
namespace testing {

grpc::string GetServiceAccountJsonKey() {
  static grpc::string json_key;
  if (json_key.empty()) {
    std::ifstream json_key_file(FLAGS_service_account_key_file);
    std::stringstream key_stream;
    key_stream << json_key_file.rdbuf();
    json_key = key_stream.str();
  }
  return json_key;
}

std::shared_ptr<ChannelInterface> CreateChannelForTestCase(
    const grpc::string& test_case) {
  GPR_ASSERT(FLAGS_server_port);
  const int host_port_buf_size = 1024;
  char host_port[host_port_buf_size];
  snprintf(host_port, host_port_buf_size, "%s:%d", FLAGS_server_host.c_str(),
           FLAGS_server_port);

  if (test_case == "service_account_creds") {
    std::unique_ptr<Credentials> creds;
    GPR_ASSERT(FLAGS_enable_ssl);
    grpc::string json_key = GetServiceAccountJsonKey();
    creds = ServiceAccountCredentials(json_key, FLAGS_oauth_scope,
                                      std::chrono::hours(1));
    return CreateTestChannel(host_port, FLAGS_server_host_override,
                             FLAGS_enable_ssl, FLAGS_use_prod_roots, creds);
  } else if (test_case == "compute_engine_creds") {
    std::unique_ptr<Credentials> creds;
    GPR_ASSERT(FLAGS_enable_ssl);
    creds = ComputeEngineCredentials();
    return CreateTestChannel(host_port, FLAGS_server_host_override,
                             FLAGS_enable_ssl, FLAGS_use_prod_roots, creds);
  } else if (test_case == "jwt_token_creds") {
    std::unique_ptr<Credentials> creds;
    GPR_ASSERT(FLAGS_enable_ssl);
    grpc::string json_key = GetServiceAccountJsonKey();
    creds = JWTCredentials(json_key, std::chrono::hours(1));
    return CreateTestChannel(host_port, FLAGS_server_host_override,
                             FLAGS_enable_ssl, FLAGS_use_prod_roots, creds);
  } else {
    return CreateTestChannel(host_port, FLAGS_server_host_override,
                             FLAGS_enable_ssl, FLAGS_use_prod_roots);
  }
}

}  // namespace testing
}  // namespace grpc
