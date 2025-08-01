#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
use t::APISIX 'no_plan';

repeat_each(1);
no_long_string();
no_root_location();
log_level("info");

run_tests;

__DATA__

=== TEST 1: sanity
--- config
    location /t {
        content_by_lua_block {
            local get_seed = require("apisix.core.utils").get_seed_from_urandom

            ngx.say("random seed ", get_seed())
            ngx.say("twice: ", get_seed() == get_seed())
        }
    }
--- request
GET /t
--- response_body_like eval
qr/random seed \d+(\.\d+)?(e\+\d+)?\ntwice: false/



=== TEST 2: parse_addr
--- config
    location /t {
        content_by_lua_block {
            local parse_addr = require("apisix.core.utils").parse_addr
            local cases = {
                {addr = "127.0.0.1", host = "127.0.0.1"},
                {addr = "127.0.0.1:90", host = "127.0.0.1", port = 90},
                {addr = "www.test.com", host = "www.test.com"},
                {addr = "www.test.com:90", host = "www.test.com", port = 90},
                {addr = "localhost", host = "localhost"},
                {addr = "localhost:90", host = "localhost", port = 90},
                {addr = "[127.0.0.1:90", host = "[127.0.0.1:90"},
                {addr = "[::1]", host = "[::1]"},
                {addr = "[::1]:1234", host = "[::1]", port = 1234},
                {addr = "[::1234:1234]:12345", host = "[::1234:1234]", port = 12345},
                {addr = "::1", host = "::1"},
            }
            for _, case in ipairs(cases) do
                local host, port = parse_addr(case.addr)
                assert(host == case.host, string.format("host %s mismatch %s", host, case.host))
                assert(port == case.port, string.format("port %s mismatch %s", port, case.port))
            end
        }
    }
--- request
GET /t



=== TEST 3: specify resolvers
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local resolvers = {"8.8.8.8"}
            core.utils.set_resolver(resolvers)
            local domain = "github.com"
            local ip_info, err = core.utils.dns_parse(domain)
            if not ip_info then
                core.log.error("failed to parse domain: ", domain, ", error: ",err)
            end
            ngx.say(require("toolkit.json").encode(ip_info))
        }
    }
--- request
GET /t
--- response_body eval
qr/"address":.+,"name":"github.com"/



=== TEST 4: default resolvers
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local domain = "github.com"
            local ip_info, err = core.utils.dns_parse(domain)
            if not ip_info then
                core.log.error("failed to parse domain: ", domain, ", error: ",err)
            end
            core.log.info("ip_info: ", require("toolkit.json").encode(ip_info))
            ngx.say("resolvers: ", require("toolkit.json").encode(core.utils.get_resolver()))
        }
    }
--- request
GET /t
--- response_body
resolvers: ["8.8.8.8","114.114.114.114"]
--- error_log eval
qr/"address":.+,"name":"github.com"/



=== TEST 5: enable_server_tokens false
--- yaml_config
apisix:
  node_listen: 1984
  enable_server_tokens: false
--- config
location /t {
    content_by_lua_block {
        local t = require("lib.test_admin").test
        local code, body = t('/apisix/admin/routes/1',
            ngx.HTTP_PUT,
             [[{
                    "upstream": {
                        "nodes": {
                            "127.0.0.1:1980": 1
                        },
                        "type": "roundrobin"
                    },
                    "uri": "/hello"
            }]]
            )

        if code >= 300 then
            ngx.status = code
            ngx.say("failed")
            return
        end

        do
            local sock = ngx.socket.tcp()

            sock:settimeout(2000)

            local ok, err = sock:connect("127.0.0.1", 1984)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local req = "GET /hello HTTP/1.0\r\nHost: www.test.com\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send http request: ", err)
                return
            end

            ngx.say("sent http request: ", bytes, " bytes.")

            while true do
                local line, err = sock:receive()
                if not line then
                    -- ngx.say("failed to receive response status line: ", err)
                    break
                end

                ngx.say("received: ", line)
            end

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        end  -- do
    }
}
--- request
GET /t
--- response_body eval
qr{connected: 1
sent http request: 62 bytes.
received: HTTP/1.1 200 OK
received: Content-Type: text/plain
received: Content-Length: 12
received: Connection: close
received: Server: APISIX
received: \nreceived: hello world
close: 1 nil}



=== TEST 6: resolve_var
--- config
    location /t {
        content_by_lua_block {
            local resolve_var = require("apisix.core.utils").resolve_var
            local cases = {
                "",
                "xx",
                "$me",
                "$me run",
                "talk with $me",
                "tell $me to",
                "$you and $me",
                "$eva and $me",
                "$you and \\$me",
                "${you}_${me}",
                "${you}${me}",
                "${you}$me",
            }
            local ctx = {
                you = "John",
                me = "David",
            }
            for _, case in ipairs(cases) do
                local res = resolve_var(case, ctx)
                ngx.say("res:", res)
            end
        }
    }
--- request
GET /t
--- response_body
res:
res:xx
res:David
res:David run
res:talk with David
res:tell David to
res:John and David
res: and David
res:John and \$me
res:John_David
res:JohnDavid
res:JohnDavid



=== TEST 7: resolve host from /etc/hosts
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local domain = "test.com"
            local ip_info, err = core.utils.dns_parse(domain)
            if not ip_info then
                core.log.error("failed to parse domain: ", domain, ", error: ",err)
                return
            end
            ngx.say("ip_info: ", require("toolkit.json").encode(ip_info))
        }
    }
--- request
GET /t
--- response_body
ip_info: {"address":"127.0.0.1","class":1,"name":"test.com","ttl":315360000,"type":1}



=== TEST 8: search host with '.org' suffix
--- yaml_config
apisix:
  node_listen: 1984
  enable_resolv_search_opt: true
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local domain = "apisix"
            local ip_info, err = core.utils.dns_parse(domain)
            if not ip_info then
                core.log.error("failed to parse domain: ", domain, ", error: ",err)
                return
            end
            ngx.say("ip_info: ", require("toolkit.json").encode(ip_info))
        }
    }
--- request
GET /t
--- response_body_like
.+"name":"apisix\.apache\.org".+



=== TEST 9: disable search option
--- yaml_config
apisix:
  node_listen: 1984
  enable_resolv_search_opt: false
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local domain = "apisix"
            local ip_info, err = core.utils.dns_parse(domain)
            if not ip_info then
                core.log.error("failed to parse domain: ", domain, ", error: ",err)
                return
            end
            ngx.say("ip_info: ", require("toolkit.json").encode(ip_info))
        }
    }
--- request
GET /t
--- error_log
error: failed to query the DNS server
--- timeout: 10



=== TEST 10: test dns config with ipv6 enable
--- yaml_config
apisix:
  enable_ipv6: true
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local domain = "ipv6.local"
            local ip_info, err = core.utils.dns_parse(domain)
            if not ip_info then
                core.log.error("failed to parse domain: ", domain, ", error: ",err)
                return
            end
            ngx.say("ip_info: ", require("toolkit.json").encode(ip_info))
        }
    }
--- request
GET /t
--- response_body
ip_info: {"address":"[::1]","class":1,"name":"ipv6.local","ttl":315360000,"type":28}



=== TEST 11: test dns config with ipv6 disable
--- yaml_config
apisix:
  enable_ipv6: false
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local domain = "ipv6.local"
            local ip_info, err = core.utils.dns_parse(domain)
            if not ip_info then
                core.log.error("failed to parse domain: ", domain, ", error: ",err)
                return
            end
            ngx.say("ip_info: ", require("toolkit.json").encode(ip_info))
        }
    }
--- request
GET /t
--- error_log
failed to parse domain: ipv6.local



=== TEST 12: get_last_index
--- config
    location /t {
        content_by_lua_block {
            local string_rfind = require("pl.stringx").rfind
            local cases = {
                {"you are welcome", "co"},
                {"nice to meet you", "meet"},
                {"chicken run", "cc"},
                {"day day up", "day"},
                {"happy new year", "e"},
                {"apisix__1928", "__"}
            }

            for _, case in ipairs(cases) do
                local res = string_rfind(case[1], case[2])
                ngx.say("res:", res)
            end
        }
    }
--- request
GET /t
--- response_body
res:12
res:9
res:nil
res:5
res:12
res:7



=== TEST 13: gethostname
--- config
    location /t {
        content_by_lua_block {
            local core = require("apisix.core")
            local hostname = core.utils.gethostname()
            ngx.say("hostname: ", hostname)
            local hostname2 = core.utils.gethostname()
            ngx.say("hostname cached: ", hostname == hostname2)
            ngx.say("hostname valid: ", hostname ~= "")

            local handle = io.popen("/bin/hostname")
            if handle then
                local system_hostname = handle:read("*a")
                handle:close()
                if system_hostname then
                    system_hostname = string.gsub(system_hostname, "\n$", "")
                    ngx.say("system hostname: ", system_hostname)
                    ngx.say("hostname match: ", hostname == system_hostname)
                else
                    ngx.say("system hostname: failed to read")
                    ngx.say("hostname match: unable to verify")
                end
            else
                ngx.say("system hostname: failed to execute /bin/hostname")
                ngx.say("hostname match: unable to verify")
            end
        }
    }
--- request
GET /t
--- response_body_like
hostname: .+
hostname cached: true
hostname valid: true
system hostname: .+
hostname match: true
