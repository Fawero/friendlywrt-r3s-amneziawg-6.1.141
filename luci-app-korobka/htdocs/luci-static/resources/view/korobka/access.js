'use strict';
'require rpc';
'require ui';
'require view';

const callStatus = rpc.declare({ object: 'luci.korobka', method: 'status' });
const callRefreshAccess = rpc.declare({ object: 'luci.korobka', method: 'refresh_access' });
const callSetManual = rpc.declare({ object: 'luci.korobka', method: 'set_manual_forward', params: [ 'confirmed' ] });

function css() {
	return E('link', { 'rel': 'stylesheet', 'href': L.resource('korobka/korobka.css') });
}

function kv(label, value, code) {
	return E('div', {'class': 'korobka-kv'}, [
		E('span', {'class': 'korobka-kv-label'}, label),
		E(code ? 'code' : 'span', {'class': code ? 'korobka-code' : 'korobka-kv-value'}, value == null || value === '' ? '—' : String(value))
	]);
}

function probeText(access) {
	if (!access) return '—';
	if (access.probe_pending) return _('Обновляется');
	if (access.observed_at) return new Date(Number(access.observed_at) * 1000).toLocaleString();
	return _('Ещё не выполнялась');
}

function endpointCard(title, protocol, port, candidate, ready) {
	return E('div', {'class': 'korobka-card'}, [
		E('div', {'class': 'korobka-card-head'}, [
			E('h3', {}, title),
			E('span', {'class': 'korobka-badge ' + (ready ? 'korobka-badge-ok' : 'korobka-badge-warn')}, ready ? _('Готов') : _('Ожидает проброс'))
		]),
		kv(_('Протокол'), protocol),
		kv(_('Порт'), port, true),
		kv(_('Endpoint'), candidate, true)
	]);
}

return view.extend({
	load: function() {
		return callStatus();
	},

	handleRefresh: function() {
		ui.showModal(_('Проверка внешнего доступа'), [
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
		const ready = !!endpoint.ready;

		let actionBlock;
		if (access.probe_pending || access.mode === 'probing') {
			actionBlock = E('div', {'class': 'korobka-callout korobka-callout-info'}, [
				E('div', {'class': 'korobka-callout-icon'}, '…'),
				E('div', {}, [E('strong', {}, _('Диагностика обновляется. ')), _('Обычные страницы при этом продолжают открываться быстро.')])
			]);
		}
		else if (access.mode === 'upstream_nat_no_automap') {
			actionBlock = E('div', {'class': 'korobka-card'}, [
				E('div', {'class': 'korobka-card-head'}, [
					E('h3', {}, _('Ручной port-forward')),
					E('span', {'class': 'korobka-badge ' + (manual ? 'korobka-badge-ok' : 'korobka-badge-warn')}, manual ? _('Подтверждён') : _('Не настроен'))
				]),
				E('p', {'class': 'korobka-subtitle'}, _('На вышестоящем маршрутизаторе автоматический проброс недоступен. Создайте ровно два правила:')),
				E('div', {'class': 'korobka-table-wrap', 'style': 'margin-top:12px'}, [
					E('table', {'class': 'table korobka-table'}, [
						E('thead', {}, E('tr', {}, [E('th', {}, _('Сервис')), E('th', {}, _('Протокол')), E('th', {}, _('Внешний порт')), E('th', {}, _('Назначение'))])),
						E('tbody', {}, [
							E('tr', {}, [E('td', {}, 'WireGuard'), E('td', {}, 'UDP'), E('td', {}, E('code', {'class': 'korobka-code'}, String(wg.port || 51821))), E('td', {}, E('code', {'class': 'korobka-code'}, (access.wan_ipv4 || 'WAN') + ':' + (wg.port || 51821)))]),
							E('tr', {}, [E('td', {}, 'Telegram MTG'), E('td', {}, 'TCP'), E('td', {}, E('code', {'class': 'korobka-code'}, String(mtg.port || 8888))), E('td', {}, E('code', {'class': 'korobka-code'}, (access.wan_ipv4 || 'WAN') + ':' + (mtg.port || 8888)))])
						])
					])
				]),
				E('div', {'class': 'korobka-callout korobka-callout-warn'}, [
					E('div', {'class': 'korobka-callout-icon'}, '!'),
					E('div', {}, _('Подтверждение не проверяет порты из Интернета автоматически. Нажимайте только после реальной настройки вышестоящего маршрутизатора.'))
				]),
				manual
					? E('button', {'class': 'btn cbi-button korobka-btn korobka-btn-danger', 'click': this.handleConfirm.bind(this, false)}, _('Сбросить подтверждение'))
					: E('button', {'class': 'btn cbi-button korobka-btn korobka-btn-primary', 'click': this.handleConfirm.bind(this, true)}, _('Я настроил проброс'))
			]);
		}
		else if (access.mode === 'direct_public') {
			actionBlock = E('div', {'class': 'korobka-callout korobka-callout-ok'}, [
				E('div', {'class': 'korobka-callout-icon'}, '✓'),
				E('div', {}, [E('strong', {}, _('Прямой public WAN. ')), _('Дополнительный NAT mapping не требуется.')])
			]);
		}
		else {
			actionBlock = E('div', {'class': 'korobka-callout korobka-callout-warn'}, [
				E('div', {'class': 'korobka-callout-icon'}, '!'),
				E('div', {}, [E('strong', {}, _('Входящий доступ требует дополнительной проверки. ')), _('Текущий режим: '), E('code', {'class': 'korobka-code'}, access.mode || 'unknown')])
			]);
		}

		return E('div', {'class': 'korobka-page'}, [
			css(),
			E('div', {'class': 'korobka-shell'}, [
				E('div', {'class': 'korobka-hero'}, [
					E('div', {}, [
						E('h2', {'class': 'korobka-title'}, _('Внешний доступ')),
						E('div', {'class': 'korobka-subtitle'}, _('Диагностика public IPv4 и входящих портов. DDNS в продукт не входит; предпочтителен статический public IPv4.'))
					]),
					E('div', {'class': 'korobka-toolbar'}, [
						E('span', {'class': 'korobka-badge ' + (ready ? 'korobka-badge-ok' : 'korobka-badge-warn')}, ready ? _('Endpoint готов') : _('Нужна настройка')),
						E('button', {'class': 'btn cbi-button korobka-btn korobka-btn-primary', 'click': this.handleRefresh.bind(this)}, _('Перепроверить сеть'))
					])
				]),
				E('div', {'class': 'korobka-grid'}, [
					E('div', {'class': 'korobka-card'}, [
						E('div', {'class': 'korobka-card-head'}, [E('h3', {}, _('Диагностика')), E('span', {'class': 'korobka-badge korobka-badge-neutral'}, access.wan_scope || 'unknown')]),
						kv(_('WAN IPv4'), access.wan_ipv4, true),
						kv(_('Public IPv4'), access.public_ipv4, true),
						kv(_('Режим'), access.mode),
						kv(_('UPnP IGD'), access.upnp && access.upnp.available ? _('Доступен') : (access.probe_pending ? _('Проверяется') : _('Недоступен'))),
						kv(_('NAT-PMP'), access.natpmp && access.natpmp.available ? _('Доступен') : (access.probe_pending ? _('Проверяется') : _('Недоступен'))),
						kv(_('Последняя проверка'), probeText(access))
					]),
					E('div', {'class': 'korobka-card'}, [
						E('div', {'class': 'korobka-card-head'}, [E('h3', {}, _('Readiness')), E('span', {'class': 'korobka-badge ' + (ready ? 'korobka-badge-ok' : 'korobka-badge-warn')}, ready ? _('Готово') : _('Ожидает действия'))]),
						kv(_('Причина'), endpoint.reason, true),
						kv(_('Ручной проброс'), manual ? _('Подтверждён') : _('Не подтверждён')),
						kv(_('Источник адреса'), endpoint.address_source || 'public_ipv4')
					])
				]),
				E('h3', {'class': 'korobka-section-title'}, _('Endpoint сервисов')),
				E('div', {'class': 'korobka-grid'}, [
					endpointCard('WireGuard', 'UDP', wg.port || 51821, wg.endpoint || wg.candidate_endpoint, !!wg.ready),
					endpointCard('Telegram MTG', 'TCP', mtg.port || 8888, mtg.endpoint || mtg.candidate_endpoint, !!mtg.ready)
				]),
				E('h3', {'class': 'korobka-section-title'}, _('Что нужно сделать')),
				actionBlock
			])
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
