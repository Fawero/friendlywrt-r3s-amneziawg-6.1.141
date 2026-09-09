'use strict';
'require rpc';
'require ui';
'require view';

const callStatus = rpc.declare({ object: 'luci.korobka', method: 'status' });
const callEnable = rpc.declare({ object: 'luci.korobka', method: 'support_enable' });
const callDisable = rpc.declare({ object: 'luci.korobka', method: 'support_disable' });
const callQr = rpc.declare({ object: 'luci.korobka', method: 'support_qr' });

function css() {
	return E('link', { 'rel': 'stylesheet', 'href': L.resource('korobka/korobka.css') });
}

function kv(label, value, code) {
	return E('div', {'class': 'korobka-kv'}, [
		E('span', {'class': 'korobka-kv-label'}, label),
		E(code ? 'code' : 'span', {'class': code ? 'korobka-code' : 'korobka-kv-value'}, value == null || value === '' ? '—' : String(value))
	]);
}

function formatLeft(seconds) {
	seconds = Math.max(0, Number(seconds || 0));
	const h = Math.floor(seconds / 3600);
	const m = Math.floor((seconds % 3600) / 60);
	const s = Math.floor(seconds % 60);
	return h + _(' ч ') + String(m).padStart(2, '0') + _(' мин ') + String(s).padStart(2, '0') + _(' сек');
}

function showQr(svg, support) {
	const box = E('div', {'style': 'text-align:center;max-width:520px;margin:auto'});
	box.innerHTML = svg;
	ui.showModal(_('Секрет техподдержки'), [
		E('div', {'class': 'korobka-callout korobka-callout-warn'}, [
			E('div', {'class': 'korobka-callout-icon'}, '!'),
			E('div', {}, [
				E('strong', {}, _('QR содержит временный SSH private key. ')),
				_('Передавайте этот снимок только сотруднику техподдержки. Ключ перестанет работать после отключения или истечения 24 часов.')
			])
		]),
		E('div', {'style': 'margin:12px 0'}, [
			E('strong', {}, (support.public_ipv4 || '—') + ':' + (support.port || '—')),
			E('br'),
			E('span', {'class': 'korobka-caption'}, support.session_id || '')
		]),
		box,
		E('div', {'class': 'right', 'style': 'margin-top:16px'}, [
			E('button', {'class': 'btn cbi-button korobka-btn', 'click': ui.hideModal}, _('Закрыть'))
		])
	]);
}

return view.extend({
	load: function() {
		return callStatus();
	},

	handleEnable: function() {
		ui.showModal(_('Включаем техподдержку'), [
			E('p', {'class': 'spinning'}, _('Создаём отдельный SSH listener, случайный порт и одноразовый ключ на 24 часа…'))
		]);
		return callEnable().then(function(res) {
			ui.hideModal();
			if (!res || res.error) {
				ui.addNotification(null, E('p', {}, res && res.error ? res.error : _('Не удалось включить техподдержку')), 'error');
				return;
			}
			window.location.reload();
		}).catch(function(err) {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, String(err)), 'error');
		});
	},

	handleDisable: function() {
		ui.showModal(_('Отключить техподдержку?'), [
			E('p', {}, _('Временный SSH listener, firewall rule и одноразовый ключ будут удалены немедленно.')),
			E('div', {'class': 'right'}, [
				E('button', {'class': 'btn cbi-button korobka-btn', 'click': ui.hideModal}, _('Отмена')),
				' ',
				E('button', {
					'class': 'btn cbi-button korobka-btn korobka-btn-danger',
					'click': function() {
						ui.showModal(_('Отключение'), [E('p', {'class': 'spinning'}, _('Закрываем временный доступ…'))]);
						callDisable().then(function(res) {
							ui.hideModal();
							if (!res || res.error) {
								ui.addNotification(null, E('p', {}, res && res.error ? res.error : _('Не удалось отключить доступ')), 'error');
								return;
							}
							window.location.reload();
						});
					}
				}, _('Отключить сейчас'))
			])
		]);
	},

	handleQr: function(support) {
		ui.showModal(_('Готовим QR'), [E('p', {'class': 'spinning'}, _('Формируем временный секрет подключения…'))]);
		return callQr().then(function(res) {
			ui.hideModal();
			if (!res || res.error || !res.svg) {
				ui.addNotification(null, E('p', {}, res && res.error ? res.error : _('QR недоступен')), 'error');
				return;
			}
			showQr(res.svg, support);
		}).catch(function(err) {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, String(err)), 'error');
		});
	},

	render: function(data) {
		const s = data || {};
		const support = s.support || { enabled: false };
		const enabled = !!support.enabled;

		const stateBadge = E('span', {
			'class': 'korobka-badge ' + (enabled ? 'korobka-badge-ok' : 'korobka-badge-neutral')
		}, enabled ? _('Включена') : _('Выключена'));

		const nodes = [
			css(),
			E('div', {'class': 'korobka-shell'}, [
				E('div', {'class': 'korobka-hero'}, [
					E('div', {}, [
						E('h2', {'class': 'korobka-title'}, _('Техподдержка')),
						E('div', {'class': 'korobka-subtitle'}, _('Временный отдельный SSH-доступ. Основной SSH на 22 порту и его настройки не изменяются.'))
					]),
					stateBadge
				]),
				E('div', {'class': 'korobka-callout korobka-callout-info'}, [
					E('div', {'class': 'korobka-callout-icon'}, 'i'),
					E('div', {}, [
						E('strong', {}, _('Зачем это нужно. ')),
						_('Если специалисту нужно посмотреть настройки Коробки, включите доступ, сфотографируйте IP, порт и QR и отправьте снимок техподдержке. Через 24 часа доступ закроется автоматически, даже если вы забудете его выключить.')
					])
				]),
				enabled ? E('div', {'class': 'korobka-grid'}, [
					E('div', {'class': 'korobka-card'}, [
						E('div', {'class': 'korobka-card-head'}, [E('h3', {}, _('Сессия поддержки')), E('span', {'class': 'korobka-badge korobka-badge-ok'}, _('Активна'))]),
						kv(_('Public IPv4'), support.public_ipv4, true),
						kv(_('Случайный SSH порт'), support.port, true),
						kv(_('Session ID'), support.session_id, true),
						kv(_('Осталось'), formatLeft(support.seconds_left)),
						kv(_('Автоотключение'), support.expires_at ? new Date(Number(support.expires_at) * 1000).toLocaleString() : '—')
					]),
					E('div', {'class': 'korobka-card'}, [
						E('div', {'class': 'korobka-card-head'}, [E('h3', {}, _('Доступность')), E('span', {'class': 'korobka-badge ' + (support.reachable ? 'korobka-badge-ok' : 'korobka-badge-warn')}, support.reachable ? _('Из Интернета') : _('Не подтверждена'))]),
						kv(_('Сетевой режим'), support.network_mode),
						kv(_('Listener'), support.listener ? _('Работает') : _('Не работает')),
						E('p', {'class': 'korobka-caption'}, support.reachable ? _('WAN Коробки имеет прямой public IPv4 — дополнительных действий не требуется.') : _('Listener на Коробке включён, но текущая схема не подтверждает прямую доступность из Интернета. На стенде с upstream NAT потребуется проброс случайного порта.'))
					])
				]) : E('div', {'class': 'korobka-card'}, [
					E('div', {'class': 'korobka-card-head'}, [E('h3', {}, _('Доступ выключен')), E('span', {'class': 'korobka-badge korobka-badge-neutral'}, _('Безопасно'))]),
					E('p', {}, _('Нет отдельного support listener, временного firewall rule или support key.'))
				]),
				E('div', {'class': 'korobka-toolbar', 'style': 'margin-top:16px'}, enabled ? [
					E('button', {'class': 'btn cbi-button korobka-btn korobka-btn-primary', 'click': this.handleQr.bind(this, support)}, _('Показать QR / секрет')),
					E('button', {'class': 'btn cbi-button korobka-btn korobka-btn-danger', 'click': this.handleDisable.bind(this)}, _('Отключить сейчас'))
				] : [
					E('button', {'class': 'btn cbi-button korobka-btn korobka-btn-primary', 'click': this.handleEnable.bind(this)}, _('Включить на 24 часа'))
				])
			])
		];

		return E('div', {'class': 'korobka-page'}, nodes);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
