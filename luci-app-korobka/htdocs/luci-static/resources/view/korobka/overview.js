'use strict';
'require rpc';
'require ui';
'require view';

const callStatus = rpc.declare({ object: 'luci.korobka', method: 'status' });
const callRefreshAccess = rpc.declare({ object: 'luci.korobka', method: 'refresh_access' });

function yn(v) {
	return v ? _('Работает') : _('Не работает');
}

function badge(ok, text) {
	return E('span', {
		'style': 'display:inline-block;padding:3px 9px;border-radius:999px;font-weight:600;background:' +
			(ok ? '#dff5e7;color:#176b3a' : '#fde7e7;color:#9b1c1c')
	}, text || yn(ok));
}

function card(title, children) {
	return E('div', {
		'class': 'cbi-section',
		'style': 'margin:0;padding:16px;border:1px solid #ddd;border-radius:12px;min-width:0'
	}, [E('h3', {'style': 'margin-top:0'}, title)].concat(children));
}

function kv(label, value) {
	return E('div', {'style': 'display:flex;justify-content:space-between;gap:16px;margin:7px 0'}, [
		E('span', {'style': 'color:#666'}, label),
		E('strong', {'style': 'text-align:right;word-break:break-word'}, value == null || value === '' ? '—' : String(value))
	]);
}

function formatBytes(v) {
	v = Number(v || 0);
	if (v < 1024) return v + ' B';
	if (v < 1024 * 1024) return (v / 1024).toFixed(1) + ' KB';
	if (v < 1024 * 1024 * 1024) return (v / 1024 / 1024).toFixed(1) + ' MB';
	return (v / 1024 / 1024 / 1024).toFixed(1) + ' GB';
}

function awgCard(title, s) {
	s = s || {};
	return card(title, [
		E('div', {'style': 'margin-bottom:8px'}, badge(!!s.up)),
		kv(_('Получено'), formatBytes(s.rx_bytes)),
		kv(_('Отправлено'), formatBytes(s.tx_bytes)),
		kv(_('Последний handshake'), Number(s.latest_handshake || 0) > 0 ? new Date(Number(s.latest_handshake) * 1000).toLocaleString() : _('Нет трафика'))
	]);
}

function probeText(access) {
	if (!access) return '—';
	if (access.probe_pending) return _('Обновляется в фоне');
	if (access.observed_at) return new Date(Number(access.observed_at) * 1000).toLocaleString();
	return _('Ещё не выполнялась');
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

		const nodes = [
			E('div', {'style': 'display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap'}, [
				E('div', {}, [
					E('h2', {'style': 'margin-bottom:4px'}, _('Коробка')),
					E('div', {'style': 'color:#666'}, _('Сводное состояние сетевого runtime'))
				]),
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'click': this.handleRefresh.bind(this)
				}, _('Перепроверить сеть'))
			])
		];

		if (access.probe_pending) {
			nodes.push(E('div', {'class': 'cbi-section warning', 'style': 'margin-top:16px'}, [
				E('strong', {}, _('Диагностика внешнего доступа обновляется в фоне. ')),
				_('Страница при этом остаётся быстрой; нажмите «Перепроверить сеть» для немедленной проверки.')
			]));
		}
		else if (!endpoint.ready) {
			nodes.push(E('div', {'class': 'cbi-section warning', 'style': 'margin-top:16px'}, [
				E('strong', {}, _('Внешний доступ ещё не готов. ')),
				_('QR можно открыть, но панель сначала объяснит, что нужно настроить. Причина: '),
				E('code', {}, endpoint.reason || 'unknown')
			]));
		}

		nodes.push(E('div', {
			'style': 'display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:14px;margin-top:16px'
		}, [
			card(_('Интернет и endpoint'), [
				E('div', {'style': 'margin-bottom:8px'}, badge(!!endpoint.ready, endpoint.ready ? _('Готов') : _('Требует настройки'))),
				kv(_('WAN IPv4'), access.wan_ipv4),
				kv(_('Public IPv4'), access.public_ipv4),
				kv(_('Режим'), access.mode),
				kv(_('Последняя диагностика'), probeText(access)),
				kv(_('WireGuard'), endpoint.wireguard && (endpoint.wireguard.endpoint || endpoint.wireguard.candidate_endpoint)),
				kv(_('MTG'), endpoint.mtg && (endpoint.mtg.endpoint || endpoint.mtg.candidate_endpoint))
			]),
			card(_('Podkop / sing-box'), [
				E('div', {'style': 'margin-bottom:8px'}, badge(!!podkop.sing_box_running)),
				kv(_('Автозапуск Podkop'), podkop.enabled ? _('Да') : _('Нет')),
				kv(_('Telegram SOCKS'), podkop.telegram_socks),
				kv(_('SOCKS готов'), podkop.telegram_socks_ready ? _('Да') : _('Нет'))
			]),
			card(_('WireGuard телефонов'), [
				E('div', {'style': 'margin-bottom:8px'}, badge(!!wg.running)),
				kv(_('UDP порт'), wg.listen_port),
				kv(_('Устройств'), wg.peer_count)
			]),
			card(_('Telegram MTG'), [
				E('div', {'style': 'margin-bottom:8px'}, badge(!!mtg.running)),
				kv(_('TCP порт'), mtg.listen_port),
				kv(_('Выход'), mtg.outbound),
				kv(_('Слушает порт'), mtg.listening ? _('Да') : _('Нет'))
			])
		]));

		nodes.push(E('h3', {'style': 'margin-top:24px'}, _('Исходящие AWG')));
		nodes.push(E('div', {
			'style': 'display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:14px'
		}, [
			awgCard('WARP', awg.warp),
			awgCard('Luxembourg', awg.lu),
			awgCard('Kazakhstan', awg.kz)
		]));

		return E('div', {}, nodes);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
