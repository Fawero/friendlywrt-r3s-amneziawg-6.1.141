'use strict';
'require rpc';
'require ui';
'require view';

const callStatus = rpc.declare({ object: 'luci.korobka', method: 'status' });
const callSetManual = rpc.declare({ object: 'luci.korobka', method: 'set_manual_forward', params: [ 'confirmed' ] });

function kv(label, value) {
	return E('div', {'style': 'display:flex;justify-content:space-between;gap:16px;margin:8px 0'}, [
		E('span', {'style': 'color:#666'}, label),
		E('strong', {'style': 'text-align:right;word-break:break-word'}, value == null || value === '' ? '—' : String(value))
	]);
}

function badge(ok, text) {
	return E('span', {
		'style': 'display:inline-block;padding:3px 9px;border-radius:999px;font-weight:600;background:' +
			(ok ? '#dff5e7;color:#176b3a' : '#fde7e7;color:#9b1c1c')
	}, text);
}

return view.extend({
	load: function() {
		return callStatus();
	},

	handleConfirm: function(value) {
		const verb = value ? _('Подтверждаем ручной проброс…') : _('Сбрасываем подтверждение…');
		ui.showModal(_('Внешний доступ'), [E('p', {'class': 'spinning'}, verb)]);

		return callSetManual(value).then(function(res) {
			ui.hideModal();
			if (!res || res.error || res.ok === false) {
				ui.addNotification(null, E('p', {}, res && res.error ? res.error : _('Не удалось сохранить состояние')), 'error');
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
		const wg = endpoint.wireguard || {};
		const mtg = endpoint.mtg || {};
		const manual = !!endpoint.manual_forward_confirmed;

		const nodes = [
			E('h2', {}, _('Внешний доступ')),
			E('p', {}, _('Коробка использует только public IPv4. DDNS в продукт не входит. Private WAN сам по себе не считается доказанным CGNAT.')),
			E('div', {'class': 'cbi-section'}, [
				E('h3', {}, _('Диагностика')),
				E('div', {'style': 'margin-bottom:10px'}, badge(!!endpoint.ready, endpoint.ready ? _('Endpoint готов') : _('Требует настройки'))),
				kv(_('WAN IPv4'), access.wan_ipv4),
				kv(_('Public IPv4'), access.public_ipv4),
				kv(_('Тип WAN'), access.wan_scope),
				kv(_('Режим'), access.mode),
				kv(_('UPnP IGD'), access.upnp && access.upnp.available ? _('Доступен') : _('Недоступен')),
				kv(_('NAT-PMP'), access.natpmp && access.natpmp.available ? _('Доступен') : _('Недоступен')),
				kv(_('Причина readiness'), endpoint.reason)
			]),
			E('div', {'class': 'cbi-section'}, [
				E('h3', {}, _('Endpoint сервисов')),
				kv(_('WireGuard'), wg.endpoint || wg.candidate_endpoint),
				kv(_('Telegram MTG'), mtg.endpoint || mtg.candidate_endpoint),
				kv(_('Ручной проброс подтверждён'), manual ? _('Да') : _('Нет'))
			])
		];

		if (access.mode === 'upstream_nat_no_automap') {
			nodes.push(E('div', {'class': 'cbi-section warning'}, [
				E('h3', {}, _('Нужен ручной port-forward')),
				E('p', {}, _('На вышестоящем маршрутизаторе автоматический проброс недоступен. Направьте только эти два порта на WAN IPv4 Коробки:')),
				E('table', {'class': 'table'}, [
					E('tr', {'class': 'tr table-titles'}, [E('th', {'class': 'th'}, _('Сервис')), E('th', {'class': 'th'}, _('Протокол')), E('th', {'class': 'th'}, _('Порт')), E('th', {'class': 'th'}, _('Назначение'))]),
					E('tr', {'class': 'tr'}, [E('td', {'class': 'td'}, 'WireGuard'), E('td', {'class': 'td'}, 'UDP'), E('td', {'class': 'td'}, String(wg.port || 51821)), E('td', {'class': 'td'}, (access.wan_ipv4 || 'WAN') + ':' + (wg.port || 51821))]),
					E('tr', {'class': 'tr'}, [E('td', {'class': 'td'}, 'Telegram MTG'), E('td', {'class': 'td'}, 'TCP'), E('td', {'class': 'td'}, String(mtg.port || 8888)), E('td', {'class': 'td'}, (access.wan_ipv4 || 'WAN') + ':' + (mtg.port || 8888))])
				]),
				E('p', {'class': 'description'}, _('Подтверждение не проверяет порт из Интернета автоматически. Нажимайте только после реальной настройки вышестоящего маршрутизатора.')),
				manual
					? E('button', {'class': 'btn cbi-button cbi-button-negative', 'click': this.handleConfirm.bind(this, false)}, _('Сбросить подтверждение'))
					: E('button', {'class': 'btn cbi-button cbi-button-apply', 'click': this.handleConfirm.bind(this, true)}, _('Проброс настроен'))
			]));
		}
		else if (access.mode === 'direct_public') {
			nodes.push(E('div', {'class': 'cbi-section'}, [E('strong', {}, _('Прямой public WAN: дополнительный NAT mapping не требуется.'))]));
		}
		else if (access.mode === 'cgnat_suspected_no_automap') {
			nodes.push(E('div', {'class': 'cbi-section warning'}, [E('strong', {}, _('CGNAT или дополнительный upstream NAT вероятен. ')), _('Входящий доступ может потребовать изменений у провайдера или на дополнительном маршрутизаторе.')]));
		}

		return E('div', {}, nodes);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
