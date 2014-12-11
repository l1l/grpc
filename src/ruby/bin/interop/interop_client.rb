# Copyright 2014, Google Inc.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
#     * Redistributions of source code must retain the above copyright
# notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above
# copyright notice, this list of conditions and the following disclaimer
# in the documentation and/or other materials provided with the
# distribution.
#     * Neither the name of Google Inc. nor the names of its
# contributors may be used to endorse or promote products derived from
# this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#!/usr/bin/env ruby
# interop_client is a testing tool that accesses a gRPC interop testing
# server and runs a test on it.
#
# Helps validate interoperation b/w different gRPC implementations.
#
# Usage: $ path/to/interop_client.rb --server_host=<hostname> \
#                                    --server_port=<port> \
#                                    --test_case=<testcase_name>

this_dir = File.expand_path(File.dirname(__FILE__))
lib_dir = File.join(File.dirname(File.dirname(this_dir)), 'lib')
$LOAD_PATH.unshift(lib_dir) unless $LOAD_PATH.include?(lib_dir)
$LOAD_PATH.unshift(this_dir) unless $LOAD_PATH.include?(this_dir)

require 'optparse'
require 'minitest'
require 'minitest/assertions'

require 'grpc'

require 'third_party/stubby/testing/proto/test.pb'
require 'third_party/stubby/testing/proto/messages.pb'

# loads the certificates used to access the test server securely.
def load_test_certs
  this_dir = File.expand_path(File.dirname(__FILE__))
  data_dir = File.join(File.dirname(File.dirname(this_dir)), 'spec/testdata')
  files = ['ca.pem', 'server1.key', 'server1.pem']
  files.map { |f| File.open(File.join(data_dir, f)).read }
end

# creates a Credentials from the test certificates.
def test_creds
  certs = load_test_certs
  creds = GRPC::Core::Credentials.new(certs[0])
end

# creates a test stub that accesses host:port securely.
def create_stub(host, port)
  address = "#{host}:#{port}"
  stub_opts = {
    :creds => test_creds,
    GRPC::Core::Channel::SSL_TARGET => 'foo.test.google.com',
  }
  logger.info("... connecting securely to #{address}")
  stub = Grpc::Testing::TestService::Stub.new(address, **stub_opts)
end

# produces a string of null chars (\0) of length l.
def nulls(l)
  raise 'requires #{l} to be +ve' if l < 0
  [].pack('x' * l)
end

# defines methods corresponding to each interop test case.
class NamedTests
  include Minitest::Assertions
  include Grpc::Testing
  include Grpc::Testing::PayloadType
  attr_accessor :assertions # required by Minitest::Assertions

  def initialize(stub)
    @assertions = 0  # required by Minitest::Assertions
    @stub = stub
  end

  # TESTING
  # PASSED
  # FAIL
  #   ruby server: fails beefcake throws on deserializing the 0-length message
  def empty_unary
    resp = @stub.empty_call(Proto2::Empty.new)
    assert resp.is_a?(Proto::Empty), 'empty_unary: invalid response'
    p 'OK: empty_unary'
  end

  # TESTING
  # PASSED
  #   ruby server
  # FAILED
  def large_unary
    req_size, wanted_response_size = 271828, 314159
    payload = Payload.new(:type => COMPRESSABLE, :body => nulls(req_size))
    req = SimpleRequest.new(:response_type => COMPRESSABLE,
                            :response_size => wanted_response_size,
                            :payload => payload)
    resp = @stub.unary_call(req)
    assert_equal(wanted_response_size, resp.payload.body.length,
                 'large_unary: payload had the wrong length')
    assert_equal(nulls(wanted_response_size), resp.payload.body,
                 'large_unary: payload content is invalid')
    p 'OK: large_unary'
  end

  # TESTING:
  # PASSED
  #   ruby server
  # FAILED
  def client_streaming
    msg_sizes = [27182, 8, 1828, 45904]
    wanted_aggregate_size = 74922
    reqs = msg_sizes.map do |x|
      req = Payload.new(:body => nulls(x))
      StreamingInputCallRequest.new(:payload => req)
    end
    resp = @stub.streaming_input_call(reqs)
    assert_equal(wanted_aggregate_size, resp.aggregated_payload_size,
                 'client_streaming: aggregate payload size is incorrect')
    p 'OK: client_streaming'
   end

  # TESTING:
  # PASSED
  #   ruby server
  # FAILED
  def server_streaming
    msg_sizes = [31415, 9, 2653, 58979]
    response_spec = msg_sizes.map { |s| ResponseParameters.new(:size => s) }
    req = StreamingOutputCallRequest.new(:response_type => COMPRESSABLE,
                                         :response_parameters => response_spec)
    resps = @stub.streaming_output_call(req)
    resps.each_with_index do |r, i|
      assert i < msg_sizes.length, 'too many responses'
      assert_equal(COMPRESSABLE, r.payload.type, 'payload type is wrong')
      assert_equal(msg_sizes[i], r.payload.body.length,
                   'payload body #{i} has the wrong length')
    end
    p 'OK: server_streaming'
  end

  # TESTING:
  # PASSED
  #   ruby server
  # FAILED
  #
  # TODO(temiola): update this test to stay consistent with the java test's
  # interpretation of the test spec.
  def ping_pong
    req_cls, param_cls= StreamingOutputCallRequest, ResponseParameters  # short
    msg_sizes = [[27182, 31415], [8, 9], [1828, 2653], [45904, 58979]]
    reqs = msg_sizes.map do |x|
      req_size, resp_size = x
      req_cls.new(:payload => Payload.new(:body => nulls(req_size)),
                  :response_type => COMPRESSABLE,
                  :response_parameters => param_cls.new(:size => resp_size))
    end
    resps = @stub.full_duplex_call(reqs)
    resps.each_with_index do |r, i|
      assert i < msg_sizes.length, 'too many responses'
      assert_equal(COMPRESSABLE, r.payload.type, 'payload type is wrong')
      assert_equal(msg_sizes[i][1], r.payload.body.length,
                   'payload body #{i} has the wrong length')
    end
    p 'OK ping_pong'
  end

end

# validates the the command line options, returning them as a Hash.
def parse_options
  options = {
    'server_host' => nil,
    'server_port' => nil,
    'test_case' => nil,
  }
  OptionParser.new do |opts|
    opts.banner = 'Usage: --server_host <server_host> --server_port server_port'
    opts.on('--server_host SERVER_HOST', 'server hostname') do |v|
      options['server_host'] = v
    end
    opts.on('--server_port SERVER_PORT', 'server port') do |v|
      options['server_port'] = v
    end
    # instance_methods(false) gives only the methods defined in that class
    test_cases = NamedTests.instance_methods(false).map { |t| t.to_s }
    test_case_list = test_cases.join(',')
    opts.on("--test_case CODE", test_cases, {}, "select a test_case",
            "  (#{test_case_list})") do |v|
      options['test_case'] = v
    end
  end.parse!

  ['server_host', 'server_port', 'test_case'].each do |arg|
    if options[arg].nil?
      raise OptionParser::MissingArgument.new("please specify --#{arg}")
    end
  end
  options
end

def main
  opts = parse_options
  stub = create_stub(opts['server_host'], opts['server_port'])
  NamedTests.new(stub).method(opts['test_case']).call
end

main