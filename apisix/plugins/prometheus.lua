--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
local core = require("apisix.core")
local exporter = require("apisix.plugins.prometheus.exporter")

local plugin_name = "prometheus"
local schema = {
    type = "object",
    properties = {
        prefer_name = {
            type = "boolean",
            default = false
        }
    },
}


local _M = {
    version = 0.2,
    priority = 500,
    name = plugin_name,
    log  = exporter.http_log,
    destroy = exporter.destroy,
    schema = schema,
    run_policy = "prefer_route",
}


function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end

    return true
end


function _M.api()
    return exporter.get_api(true)
end


function _M.init()
    local local_conf = core.config.local_conf()
    local enabled_in_stream = core.table.array_find(local_conf.stream_plugins, "prometheus")
    exporter.http_init(enabled_in_stream)
end


return _M
