'use strict';
'require rpc';
'require ui';
'require view';

const callStatus = rpc.declare({ object: 'luci.korobka', method: 'status' });
const callRefreshAccess = rpc.declare({ object: 'luci.korobka', method: 'refresh_access' });

function css() {
	return E('link', { 'rel': 'stylesheet', 'href': L.resource('korobka/korobka.css') });
}

function badge(ok, goodText, badText) {
	return E('span', {
		'class': 'korobka-badge ' + (ok ? 'korobka-badge-ok' : 'korobka-badge-warn')
	}, ok ? goodText : badText);
}

function kv(label, value, code) {
	return E('div', {'class': 'korobka-kv'}, [
		E('span', {'class': 'korobka-kv-label'}, label),
		E(code ? 'code' : 'span', {'class': code ? 'korobka-code' : 'korobka-kv-value'}, value == null || value === '' ? '—' : String(value))
	]);
}

function formatBytes(v) {
	v = Number(v || 0);
	if (v < 1024) return v + ' B';
	if (v < 1024 * 1024) return (v / 1024).toFixed(1) + ' KB';
	if (v < 1024 * 1024 * 1024) return (v / 1024 / 1024).toFixed(1) + ' MB';
	return (v / 1024 / 1024 / 1024).toFixed(1) + ' GB';
}

function handshake(ts) {
	return Number(ts || 0) > 0 ? new Date(Number(ts) * 1000).toLocaleString() : _('Нет трафика');
}

function probeText(access) {
	if (!access) return '—';
	if (access.probe_pending) return _('Обновляется');
	if (access.observed_at) return new Date(Number(access.observed_at) * 1000).toLocaleString();
	return _('Ещё не выполнялась');
}

function card(title, stateNode, rows) {
	return E('div', {'class': 'korobka-card'}, [
		E('div', {'class': 'korobka-card-head'}, [E('h3', {}, title), stateNode]),
		E('div', {}, rows)
	]);
}

function awgCard(title, s) {
	s = s || {};
	return card(title, badge(!!s.up, _('Работает'), _('Не работает')), [
		kv(_('Получено'), formatBytes(s.rx_bytes)),
		kv(_('Отправлено'), formatBytes(s.tx_bytes)),
		kv(_('Последний handshake'), handshake(s.latest_handshake))
	]);
}

return view.extend({
	load: function() {
		return callStatus();
	},

	handleRefresh: function() {
		ui.showModal(_('Диагностика внешнего доступа'), [
			E('p', {'class': 'spinning'}, _('Проверяем public IPv4, UPnP и NAT-PMP…'))
		]);

		return callRefreshAccess().then(function(res) {
			ui.hideModal();
			if (!res || res.error) {
				ui.addNotification(null, E('p', {}, res && res.error ? res.error : _('Диагностика не выполнена')), 'error');
				return;
			}
			window.location.reload();
		}).catch(function(err) {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, String(err)), 'error');
		});
	},

	render: function(data) {
		const s = data || {};
		const access = s.access || {};
		const endpoint = s.endpoint || {};
		const podkop = s.podkop || {};
		const wg = s.wireguard || {};
		const mtg = s.mtg || {};
		const awg = s.awg || {};
		const local = s.local_management || {};
		const support = s.support || { enabled: false };

		const callout = endpoint.ready
			? E('div', {'class': 'korobka-callout korobka-callout-ok'}, [
				E('div', {'class': 'korobka-callout-icon'}, '✓'),
				E('div', {}, [E('strong', {}, _('Внешний endpoint готов. ')), _('WireGuard и Telegram QR можно выдавать клиентам.')])
			])
			: E('div', {'class': 'korobka-callout korobka-callout-warn'}, [
				E('div', {'class': 'korobka-callout-icon'}, '!'),
				E('div', {}, [
					E('strong', {}, _('Нужна настройка внешнего доступа. ')),
					_('Причина: '), E('code', {'class': 'korobka-code'}, endpoint.reason || 'unknown'),
					E('br'),
					E('span', {'class': 'korobka-caption'}, _('QR-кнопки уже можно нажимать — панель покажет, что именно нужно сделать.'))
				])
			]);

		return E('div', {'class': 'korobka-page'}, [
			css(),
			E('div', {'class': 'korobka-shell'}, [
				E('div', {'class': 'korobka-hero'}, [
					E('div', {}, [
						E('h2', {'class': 'korobka-title'}, _('Коробка')),
						E('div', {'class': 'korobka-subtitle'}, _('Состояние VPN-выходов, входящего WireGuard, Telegram MTProxy и управления Коробкой в одном месте.'))
					]),
					E('div', {'class': 'korobka-toolbar'}, [
						E('button', {
							'class': 'btn cbi-button korobka-btn korobka-btn-primary',
							'click': this.handleRefresh.bind(this)
						}, _('Перепроверить сеть'))
					])
				]),
				callout,
				E('div', {'class': 'korobka-grid'}, [
					card(_('Интернет и endpoint'), badge(!!endpoint.ready, _('Готов'), _('Нужна настройка')), [
						kv(_('WAN IPv4'), access.wan_ipv4, true),
						kv(_('Public IPv4'), access.public_ipv4, true),
						kv(_('Режим'), access.mode),
						kv(_('Последняя диагностика'), probeText(access))
					]),
					card(_('Podkop / sing-box'), badge(!!podkop.sing_box_running, _('Работает'), _('Не работает')), [
						kv(_('Автозапуск'), podkop.enabled ? _('Да') : _('Нет')),
						kv(_('Telegram SOCKS'), podkop.telegram_socks, true),
						kv(_('SOCKS готов'), podkop.telegram_socks_ready ? _('Да') : _('Нет'))
					]),
					card(_('WireGuard телефонов'), badge(!!wg.running, _('Работает'), _('Не работает')), [
						kv(_('UDP порт'), wg.listen_port, true),
						E('div', {'class': 'korobka-kv'}, [
							E('span', {'class': 'korobka-kv-label'}, _('Устройств')),
							E('span', {'class': 'korobka-metric'}, String(wg.peer_count || 0))
						]),
						kv(_('Candidate'), endpoint.wireguard && endpoint.wireguard.candidate_endpoint, true)
					]),
					card(_('Telegram MTG'), badge(!!mtg.running && !!mtg.listening, _('Работает'), _('Не работает')), [
						kv(_('TCP порт'), mtg.listen_port, true),
						kv(_('Выход'), mtg.outbound, true),
						kv(_('Candidate'), endpoint.mtg && endpoint.mtg.candidate_endpoint, true)
					])
				]),
				E('h3', {'class': 'korobka-section-title'}, _('Управление Коробкой')),
				E('div', {'class': 'korobka-grid'}, [
					card(_('Локальное управление'), badge(!!local.configured, _('Настроено'), _('Не настроено')), [
						kv(_('Основной адрес'), local.primary_url, true),
						kv(_('Fallback'), local.fallback_url, true),
						kv(_('LAN Коробки'), local.lan_ipv4, true),
						kv(_('DNS alias'), local.fqdn, true)
					]),
					E('div', {'class': 'korobka-card'}, [
						E('div', {'class': 'korobka-card-head'}, [
							E('h3', {}, _('Техподдержка')),
							E('span', {'class': 'korobka-badge ' + (support.enabled ? 'korobka-badge-ok' : 'korobka-badge-neutral')}, support.enabled ? _('Включена') : _('Выключена'))
						]),
						kv(_('Session ID'), support.session_id, true),
						kv(_('Случайный порт'), support.port, true),
						kv(_('Внешняя доступность'), support.reachable ? _('Подтверждена') : _('Не подтверждена')),
						E('div', {'style': 'margin-top:12px'}, [
							E('button', {
								'class': 'btn cbi-button korobka-btn korobka-btn-soft',
								'click': function() { window.location.href = L.url('admin/korobka/support'); }
							}, support.enabled ? _('Открыть сессию') : _('Открыть техподдержку'))
						])
					])
				]),
				E('h3', {'class': 'korobka-section-title'}, _('Исходящие VPN-выходы')),
				E('div', {'class': 'korobka-grid-3'}, [
					awgCard('WARP', awg.warp),
					awgCard('Luxembourg', awg.lu),
					awgCard('Kazakhstan', awg.kz)
				])
			])
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
