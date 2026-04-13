-- Copyright (C) 2026 zzz 802.1X Client - LuCI Configuration Module
-- Licensed under Apache 2.0

local fs = require "nixio.fs"

local m, s, o

m = Map("zzz", "802.1X 客户端配置",
	"配置 zzz 802.1X EAPOL 认证客户端，用于校园网或企业网接入。")

-- -----------------------------------------------------------
--  Section: main
-- -----------------------------------------------------------
s = m:section(NamedSection, "main", "zzz", "基础设置")
s.addremove = false

o = s:option(Value, "device", "网络接口",
	"用于 802.1X 认证的网络接口 (例如: eth0 或 wan)。")
o.rmempty = false
o.placeholder = "eth0"

o = s:option(Value, "username", "用户名",
	"您的 802.1X 校园网/企业网账号。")
o.rmempty = false

o = s:option(Value, "password", "密码",
	"您的 802.1X 校园网/企业网密码。")
o.password = true
o.rmempty = false

-- Advanced EAP settings
o = s:option(ListValue, "eap_method", "EAP 认证方法",
	"当前后端仅实现 EAP-MD5，其余方法保留供未来扩展，选择后不影响实际认证行为。")
o:value("", "默认 (EAP-MD5)")
o:value("MD5", "EAP-MD5")
o:value("PEAP", "EAP-PEAP (暂不支持)")
o:value("TTLS", "EAP-TTLS (暂不支持)")
o:value("TLS", "EAP-TLS (暂不支持)")
o.rmempty = true

o = s:option(ListValue, "phase2", "第二阶段认证 (Phase 2)",
	"EAP-MD5 不使用第二阶段，此选项仅在未来支持 PEAP/TTLS 后生效。")
o:value("", "无 / 自动")
o:value("MSCHAPv2", "MSCHAPv2")
o:value("MSCHAP", "MSCHAP")
o:value("PAP", "PAP")
o:value("CHAP", "CHAP")
o:value("GTC", "GTC")
o.rmempty = true

-- -----------------------------------------------------------
--  Section: Auto-Reconnect
-- -----------------------------------------------------------
s = m:section(NamedSection, "main", "zzz", "自动重连")
s.addremove = false

o = s:option(Flag, "auto_reconnect", "启用自动重连",
	"当网络断开或认证掉线时自动重新连接。")
o.rmempty = false

o = s:option(Value, "check_interval", "检测间隔 (秒)",
	"多久检查一次网络连通性。")
o.datatype = "uinteger"
o.default = "30"

o = s:option(Value, "max_retries", "最大重试次数",
	"断线后的最大重连次数 (-1 表示无限重试)。")
o.datatype = "integer"
o.default = "-1"

o = s:option(Value, "retry_delay", "重试延迟 (秒)",
	"每次重试之间的等待时间。")
o.datatype = "uinteger"
o.default = "10"

o = s:option(Value, "gateway_ip", "网关 IP",
	"自定义连通性检查的 IP 地址。留空则自动检测网关或 Ping 223.5.5.5。")
o.datatype = "ipaddr"
o.rmempty = true

-- -----------------------------------------------------------
--  Section: Anti-Detection
-- -----------------------------------------------------------
s = m:section(NamedSection, "main", "zzz", "防检测 (校园网突破)")
s.addremove = false

o = s:option(Flag, "fix_ttl", "固定 TTL (防共享检测)",
	"强制将数据包的 TTL 锁定为 64，防止路由器被检测出共享网络。(依赖 iptables-mod-ipopt)")
o.rmempty = false

o = s:option(Flag, "disable_ipv6", "禁用 IPv6",
	"防止 IPv6 泄露终端设备的真实 MAC 和 IP 地址给网关。")
o.rmempty = false

-- -----------------------------------------------------------
--  Custom save handler: sync to /etc/config.ini
-- -----------------------------------------------------------
m.on_after_commit = function(self)
	local uci = require("luci.model.uci").cursor()
	local vals = uci:get_all("zzz", "main") or {}
	
	local f = io.open("/etc/config.ini", "w")
	if f then
		f:write("[auth]\n")
		f:write("device=" .. tostring(vals.device or "eth0") .. "\n")
		f:write("username=" .. tostring(vals.username or "") .. "\n")
		f:write("password=" .. tostring(vals.password or "") .. "\n")

		if vals.eap_method and vals.eap_method ~= "" then
			f:write("\n[eap]\n")
			f:write("method=" .. tostring(vals.eap_method) .. "\n")
			if vals.phase2 and vals.phase2 ~= "" then
				f:write("phase2=" .. tostring(vals.phase2) .. "\n")
			end
		end

		if vals.auto_reconnect == "1" then
			f:write("\n[watchdog]\n")
			f:write("enabled=1\n")
			f:write("interval=" .. tostring(vals.check_interval or "30") .. "\n")
			f:write("max_retries=" .. tostring(vals.max_retries or "-1") .. "\n")
			f:write("retry_delay=" .. tostring(vals.retry_delay or "10") .. "\n")
			if vals.gateway_ip and vals.gateway_ip ~= "" then
				f:write("gateway_ip=" .. tostring(vals.gateway_ip) .. "\n")
			end
		end

		if vals.fix_ttl == "1" or vals.disable_ipv6 == "1" then
			f:write("\n[anti_detection]\n")
			if vals.fix_ttl == "1" then f:write("fix_ttl=1\n") end
			if vals.disable_ipv6 == "1" then f:write("disable_ipv6=1\n") end
		end

		f:close()
		
		-- Restart service to apply new config
		os.execute("/etc/init.d/zzz restart >/dev/null 2>&1")
	end
end

-- Function to read log output via logread
function m.action_logread()
	local result = {}
	local f = io.popen('logread | grep -i "zzz" | tail -n 50 2>/dev/null')
	if f then
		result.log = f:read("*a") or ""
		f:close()
		if result.log == "" then
			result.log = "(系统日志中暂无 zzz 的相关输出)"
		end
	else
		result.log = "(无法读取系统日志)"
	end
	return result.log
end

-- Add a custom section to display status and logs
s2 = m:section(NamedSection, "main", "zzz", "服务状态与日志")
s2.addremove = false

o2 = s2:option(DummyValue, "_status", "运行状态")
o2.rawhtml = true
o2.cfgvalue = function(self, section)
	local pid_f = io.popen("pidof zzz 2>/dev/null")
	local pid = pid_f:read("*line")
	pid_f:close()

	if pid and pid ~= "" then
		return '<span style="color:green; font-weight:bold;">运行中 (PID: ' .. pid .. ')</span>'
	else
		return '<span style="color:blue; font-weight:bold;">已停止</span>'
	end
end

-- 手动控制按钮
o_run = s2:option(Button, "_run", "启动/重启服务")
o_run.inputtitle = "▶ 运行 / 重启"
o_run.inputstyle = "apply"
o_run.write = function(self, section)
	os.execute("logger -t zzz-init 'WebUI: Start/Restart button clicked'")
	os.execute("/etc/init.d/zzz restart >/dev/null 2>&1")
end

o_stop = s2:option(Button, "_stop", "停止服务")
o_stop.inputtitle = "■ 停止"
o_stop.inputstyle = "reset"
o_stop.write = function(self, section)
	os.execute("logger -t zzz-init 'WebUI: Stop button clicked'")
	os.execute("/etc/init.d/zzz stop >/dev/null 2>&1")
end

o3 = s2:option(DummyValue, "_logs", "最近日志")
o3.rawhtml = true
o3.cfgvalue = function(self, section)
	local logs = m.action_logread()
	-- Escape html entities in logs
	logs = logs:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
	return '<pre style="background:#1e1e1e; color:#d4d4d4; padding:10px; border-radius:4px; max-height:200px; overflow-y:auto; font-size:12px; font-family:monospace; margin-bottom:0; white-space:pre-wrap;">' .. logs .. '</pre>'
end

return m
