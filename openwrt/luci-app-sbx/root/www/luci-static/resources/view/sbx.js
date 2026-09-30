'use strict';
'require view';
'require uci';
'require fs';
'require ui';

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('sbx'),
			fs.exec_direct('/usr/bin/sbx-luci-status'),
			fs.exec_direct('/usr/bin/sbx-zashboard', [ 'status' ]),
			fs.read('/etc/sing-box/config.json')
		]);
	},

	render: function(data) {
		var status = {}, panel = {};
		try { status = JSON.parse(commandOutput(data[1]) || '{}'); } catch (e) {}
		try { panel = JSON.parse(commandOutput(data[2]) || '{}'); } catch (e) {}

		var root = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('SBX')),
			E('div', { 'class': 'cbi-map-descr' }, _('旁路由 sing-box 管理面板')),
			E('div', { 'class': 'sbx-tabs' }, [
				E('button', { 'class': 'sbx-tab active', 'data-tab': 'status' }, _('运行状态')),
				E('button', { 'class': 'sbx-tab', 'data-tab': 'config' }, _('配置文件')),
				E('button', { 'class': 'sbx-tab', 'data-tab': 'panel' }, _('面板')),
				E('button', { 'class': 'sbx-tab', 'data-tab': 'current' }, _('当前配置')),
				E('button', { 'class': 'sbx-tab', 'data-tab': 'logs' }, _('日志'))
			]),
			E('div', { 'class': 'sbx-runtime-bar' }, [
				E('strong', {}, _('运行状态：')),
				E('span', { 'data-status': 'top-running', 'class': status.running ? 'sbx-running' : 'sbx-stopped' }, status.running ? 'running' : 'stopped'),
				E('button', { name: 'sbx-start', 'class': 'cbi-button cbi-button-action' }, _('运行')),
				E('button', { name: 'sbx-stop', 'class': 'cbi-button' }, _('停止')),
				E('span', { name: 'sbx-service-result', 'class': 'sbx-result' })
			]),
			E('div', { 'class': 'sbx-pane active', 'data-pane': 'status' }, statusPane(status)),
			E('div', { 'class': 'sbx-pane', 'data-pane': 'config' }, configPane()),
			E('div', { 'class': 'sbx-pane', 'data-pane': 'panel' }, panelPane(panel)),
			E('div', { 'class': 'sbx-pane', 'data-pane': 'current' }, currentPane(data[3])),
			E('div', { 'class': 'sbx-pane', 'data-pane': 'logs' }, logsPane())
		]);

		var style = E('style', {}, [
			':root{color-scheme:dark}.sbx-tabs{display:flex;gap:4px;border-bottom:1px solid var(--border-color,#444);margin:12px 0}.sbx-tab{padding:9px 16px;border:1px solid var(--border-color,#444);color:var(--text-color,#eee);background:var(--background-color,#1b1b1b);cursor:pointer}.sbx-tab.active{background:var(--primary-color,#0069a6);color:#fff}.sbx-pane{display:none;padding:8px 0}.sbx-pane.active{display:block}.sbx-card{border:1px solid var(--border-color,#444);padding:16px;margin:8px 0;background:var(--background-color,#1b1b1b);color:var(--text-color,#eee)}.sbx-grid{display:grid;grid-template-columns:180px 1fr;gap:10px;max-width:760px}.sbx-status-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:12px;margin-bottom:14px}.sbx-metric{border:1px solid var(--border-color,#3d3d3d);border-radius:8px;background:rgba(255,255,255,.035);padding:14px}.sbx-metric-label{font-size:12px;color:var(--muted-color,#aaa);margin-bottom:8px}.sbx-metric-value{font-size:20px;font-weight:700;line-height:1.2}.sbx-section-title{font-weight:700;margin:16px 0 10px}.sbx-version-list{display:grid;grid-template-columns:1fr;gap:10px}.sbx-version-row{display:grid;grid-template-columns:minmax(150px,1fr) minmax(120px,auto) minmax(120px,auto);align-items:center;gap:12px;border:1px solid var(--border-color,#3d3d3d);border-radius:8px;background:rgba(255,255,255,.025);padding:10px 12px}.sbx-version-name{font-weight:700}.sbx-version-meta{color:var(--muted-color,#aaa);font-size:12px}.sbx-mode-row{display:flex;align-items:center;gap:10px;flex-wrap:wrap}.sbx-mode-row select{min-width:180px}.sbx-inline-update{display:flex;align-items:center;gap:10px;flex-wrap:wrap}.sbx-grid input,.sbx-grid select,.sbx-mode-row select{box-sizing:border-box;color:var(--text-color,#eee);background:var(--input-background-color,#252525);border:1px solid var(--border-color,#555);padding:6px}.sbx-grid input,.sbx-grid select{width:100%}.sbx-mono{width:100%;min-height:480px;box-sizing:border-box;font-family:monospace;white-space:pre;overflow:auto;color:var(--text-color,#eee);background:var(--input-background-color,#151515);border:1px solid var(--border-color,#555)}.sbx-log{height:560px;overflow:auto;background:#111;color:#eee;padding:12px;white-space:pre-wrap;font-family:monospace;border:1px solid var(--border-color,#444)}.sbx-card a{color:var(--link-color,#69b7ff)}.sbx-result{margin-top:8px;min-height:20px}.sbx-result.success{color:#72d572}.sbx-result.error{color:#ff7777}'
		]);
		root.appendChild(style);
		root.appendChild(E('style', {}, [
			'.sbx-runtime-bar{display:flex;align-items:center;gap:14px;padding:12px;margin:8px 0}.sbx-runtime-bar [data-status="top-running"]{display:inline-block;min-width:70px;font-weight:700}.sbx-runtime-bar .sbx-running{color:#39d353}.sbx-runtime-bar .sbx-stopped{color:#ff4d4f}.sbx-runtime-bar [name="sbx-start"],.sbx-runtime-bar [name="sbx-stop"]{margin-left:6px}'
		]));

		root.querySelectorAll('.sbx-tab').forEach(function(tab) {
			tab.addEventListener('click', function() {
				root.querySelectorAll('.sbx-tab,.sbx-pane').forEach(function(node) { node.classList.remove('active'); });
				tab.classList.add('active');
				root.querySelector('[data-pane="' + tab.dataset.tab + '"]').classList.add('active');
			});
		});

		var profile = root.querySelector('[name="sbx-profile"]');
		profile.value = status.mode || 'proxy-only';
		profile.dataset.appliedMode = status.mode || 'proxy-only';
		var apply = root.querySelector('[name="sbx-apply"]');
		var resultBox = root.querySelector('[name="sbx-action-result"]');
		apply.addEventListener('click', function() {
			var mode = profile.value;
			apply.disabled = true;
			resultBox.className = 'sbx-result';
			resultBox.textContent = _('正在应用配置并重启 sing-box…');
			fs.exec_direct('/usr/bin/sbx-luci-action', [ 'apply-mode', mode ]).then(function(result) {
				var error = commandError(result);
				if (error) {
					resultBox.className = 'sbx-result error';
					resultBox.textContent = _('应用失败：') + error;
				} else {
					resultBox.className = 'sbx-result success';
					resultBox.textContent = _('已应用并重启 sing-box：') + mode;
					profile.dataset.appliedMode = mode;
				}
				apply.disabled = false;
			}).catch(function(error) {
				resultBox.className = 'sbx-result error';
				resultBox.textContent = _('应用失败：') + error;
				apply.disabled = false;
			});
		});

		function serviceAction(action) {
			var resultBox = root.querySelector('[name="sbx-service-result"]');
			resultBox.className = 'sbx-result';
			resultBox.textContent = action == 'start' ? _('正在运行 sing-box…') : _('正在停止 sing-box…');
			return fs.exec_direct('/usr/bin/sbx-luci-action', [ action ]).then(function(result) {
				var error = commandError(result);
				if (error) {
					resultBox.className = 'sbx-result error';
					resultBox.textContent = _('操作失败：') + error;
				} else {
					resultBox.className = 'sbx-result success';
					resultBox.textContent = action == 'start' ? _('sing-box 已运行') : _('sing-box 已停止');
					refresh();
				}
			});
		}
		root.querySelector('[name="sbx-start"]').addEventListener('click', function() { serviceAction('start'); });
		root.querySelector('[name="sbx-stop"]').addEventListener('click', function() { serviceAction('stop'); });

		var save = root.querySelector('[name="sbx-save-config"]');
		save.addEventListener('click', function() {
			var tun = root.querySelector('[name="sbx-tun-url"]').value;
			var tproxy = root.querySelector('[name="sbx-tproxy-url"]').value;
			uci.set('sbx', 'main', 'tun_config_url', tun);
			uci.set('sbx', 'main', 'tproxy_config_url', tproxy);
			uci.save().then(function() { return uci.apply(); }).then(function() {
				root.querySelector('[name="sbx-config-result"]').textContent = _('配置链接已保存');
			}).catch(function(error) {
				root.querySelector('[name="sbx-config-result"]').textContent = _('保存失败：') + error;
			});
		});

		var logBox = root.querySelector('.sbx-log');
		Promise.all([
			fs.exec_direct('/usr/bin/sbx-luci-version', [ 'singbox' ]),
			fs.exec_direct('/usr/bin/sbx-luci-version', [ 'sbx' ])
		]).then(function(values) {
			updateVersion(root, 'singbox', values[0]);
			updateVersion(root, 'sbx', values[1]);
		});
		root.querySelectorAll('[data-update-kind]').forEach(function(button) {
			button.addEventListener('click', function() {
				var kind = button.dataset.updateKind;
				var result = root.querySelector('[data-update-result="' + kind + '"]');
				if (button.disabled || button.dataset.updateAvailable !== 'true') {
					result.className = 'sbx-result';
					result.textContent = _('当前已是最新版');
					return;
				}
				button.disabled = true;
				result.className = 'sbx-result';
				result.textContent = _('正在更新…');
				fs.exec_direct('/usr/bin/sbx-luci-action', [ 'update-' + kind ]).then(function(value) {
					var error = commandError(value);
					result.className = error ? 'sbx-result error' : 'sbx-result success';
					result.textContent = error ? _('更新失败：') + error : _('更新成功，请刷新页面确认版本');
					button.disabled = false;
				}).catch(function(error) {
					result.className = 'sbx-result error';
					result.textContent = _('更新失败：') + error;
					button.disabled = false;
				});
			});
		});
		function refresh() {
			return Promise.all([
				fs.exec_direct('/usr/bin/sbx-luci-status'),
				fs.exec_direct('/usr/bin/sbx-luci-action', [ 'log' ])
			]).then(function(values) {
				try { updateStatus(root, JSON.parse(commandOutput(values[0]) || '{}')); } catch (e) {}
				var logText = commandOutput(values[1]);
				if (logBox && logText) { logBox.textContent = logText; logBox.scrollTop = logBox.scrollHeight; }
			});
		}
		refresh();
		var timer = setInterval(refresh, 3000);
		root.addEventListener('remove', function() { clearInterval(timer); });
		return root;
	}
});

function commandOutput(value) {
	if (Array.isArray(value)) return value[0] || '';
	return typeof value === 'string' ? value : '';
}

function statusPane(status) {
	var mode = status.mode || 'proxy-only';
	return E('div', { 'class': 'sbx-card' }, [
		E('div', { 'class': 'sbx-status-grid' }, [
			metricCard(_('运行状态'), E('span', { 'data-status': 'running', 'class': status.running ? 'sbx-running' : 'sbx-stopped' }, status.running ? _('运行中') : _('已停止'))),
			metricCard(_('运行模式'), mode === 'tun' ? 'TUN' : mode === 'tproxy' ? 'TProxy' : _('仅 SOCKS/HTTP')),
			metricCard(_('CPU 占用'), E('span', { 'data-status': 'cpu' }, (status.cpu || '0') + '%')),
			metricCard(_('内存占用'), E('span', { 'data-status': 'memory' }, (status.memory || '0') + '%'))
		]),
		E('div', { 'class': 'sbx-section-title' }, _('版本信息')),
		E('div', { 'class': 'sbx-version-list' }, [
			versionRow('sing-box', E('span', { 'data-status': 'version', 'data-version': 'local-singbox' }, status.version || '-'), E('span', { 'data-version': 'latest-singbox' }, _('查询中…')), 'singbox'),
			versionRow('SBX/OpenWrt', E('span', { 'data-version': 'local-sbx' }, _('查询中…')), E('span', { 'data-version': 'latest-sbx' }, _('查询中…')), 'sbx')
		]),
		E('div', { 'class': 'sbx-section-title' }, _('运行模式')),
		E('div', { 'class': 'sbx-mode-row' }, [
			E('select', { name: 'sbx-profile' }, [
				E('option', { value: 'tun', selected: mode === 'tun' }, 'TUN'),
				E('option', { value: 'tproxy', selected: mode === 'tproxy' }, 'TProxy'),
				E('option', { value: 'proxy-only', selected: mode === 'proxy-only' }, _('仅 SOCKS/HTTP'))
			]),
			E('button', { name: 'sbx-apply', 'class': 'cbi-button cbi-button-action' }, _('应用并重启')),
			E('span', { name: 'sbx-action-result', 'class': 'sbx-result' })
		])
	]);
}

function metricCard(label, value) {
	return E('div', { 'class': 'sbx-metric' }, [
		E('div', { 'class': 'sbx-metric-label' }, label),
		E('div', { 'class': 'sbx-metric-value' }, value)
	]);
}

function versionRow(name, local, latest, kind) {
	return E('div', { 'class': 'sbx-version-row' }, [
		E('div', {}, [E('div', { 'class': 'sbx-version-name' }, name), E('div', { 'class': 'sbx-version-meta' }, [_('当前：'), local])]),
		E('div', { 'class': 'sbx-inline-update' }, [E('span', { 'class': 'sbx-version-meta' }, _('最新：')), latest, E('button', { 'data-update-kind': kind, 'data-update-available': 'false', disabled: true, 'class': 'cbi-button cbi-button-action' }, _('更新'))]),
		E('span', { 'data-update-result': kind, 'class': 'sbx-result' })
	]);
}

function configPane() {
	return E('div', { 'class': 'sbx-card' }, [
		E('div', { 'class': 'sbx-grid' }, [
			E('label', {}, _('TUN 配置链接')), E('input', { name: 'sbx-tun-url', value: uci.get('sbx', 'main', 'tun_config_url') || '', type: 'url' }),
			E('label', {}, _('TProxy 配置链接')), E('input', { name: 'sbx-tproxy-url', value: uci.get('sbx', 'main', 'tproxy_config_url') || '', type: 'url' }),
			E('label', {}, ''), E('div', {}, [E('button', { name: 'sbx-save-config', 'class': 'cbi-button cbi-button-save' }, _('保存配置链接')), E('div', { name: 'sbx-config-result', 'class': 'sbx-result' })])
		])
	]);
}

function panelPane(panel) {
	return E('div', { 'class': 'sbx-card' }, [
		E('p', {}, _('面板版本：') + (panel.version || _('未安装'))),
		panel.installed ? E('p', {}, [E('a', { href: '/zashboard/', target: '_blank' }, _('打开 Zashboard 面板'))]) : E('p', {}, _('暂无已安装面板'))
	]);
}

function currentPane(content) {
	return E('div', { 'class': 'sbx-card' }, [E('textarea', { 'class': 'sbx-mono', readonly: true }, content || '')]);
}

function logsPane() { return E('div', { 'class': 'sbx-card' }, [E('pre', { 'class': 'sbx-log' }, _('正在读取日志…'))]); }
function commandError(value) {
	var output = commandOutput(value);
	if (Array.isArray(value) && value[1]) return value[1];
	return output.indexOf('failed') >= 0 || output.indexOf('error') >= 0 ? output : '';
}
function updateStatus(root, status) {
	var values = { version: status.version || '-', running: status.running ? _('运行中') : _('已停止'), cpu: (status.cpu || '0') + '%', memory: (status.memory || '0') + '%' };
	Object.keys(values).forEach(function(key) { var node = root.querySelector('[data-status="' + key + '"]'); if (node) node.textContent = values[key]; });
	var top = root.querySelector('[data-status="top-running"]');
	if (top) { top.textContent = status.running ? 'running' : 'stopped'; top.className = status.running ? 'sbx-running' : 'sbx-stopped'; }
}
function updateVersion(root, kind, value) {
	try {
		var version = JSON.parse(commandOutput(value) || '{}');
		var local = root.querySelector('[data-version="' + (kind === 'sbx' ? 'local-sbx' : 'local-singbox') + '"]');
		var latest = root.querySelector('[data-version="latest-' + kind + '"]');
		if (local) local.textContent = version.local || '-';
		if (latest) latest.textContent = version.latest || '-';
		var button = root.querySelector('[data-update-kind="' + kind + '"]');
		if (button) {
			button.disabled = !version.update_available;
			button.dataset.updateAvailable = version.update_available ? 'true' : 'false';
		}
	} catch (e) {}
}
