'use strict';
'require rpc';
'require ui';
'require view';

const callStatus = rpc.declare({ object: 'luci.korobka', method: 'status' });
const callQr = rpc.declare({ object: 'luci.korobka', method: 'mtg_qr' });

function css() {
	return E('link', { 'rel': 'stylesheet', 'href': L.resource('korobka/korobka.css') });
}

function notifyError(message) {
	ui.addNotification(null, E('p', {}, message || _('Неизвестная ошибка')), 'error');
}

function showSvg(title, svg) {
	const box = E('div', {'style': 'text-align:center;max-width:460px;margin:auto'});
	box.innerHTML = svg;
	ui.showModal(title, [
		box,
		E('div', {'class': 'right', 'style': 'margin-top:16px'}, [
			E('button', {'class': 'btn cbi-button korobka-btn', 'click': ui.hideModal}, _('Закрыть'))
		])
	]);
}

function kv(label, value, code) {
	return E('div', {'class': 'korobka-kv'}, [
		E('span', {'class': 'korobka-kv-label'}, label),
		E(code ? 'code' : 'span', {'class': code ? 'korobka-code' : 'korobka-kv-value'}, value == null || value === '' ? '—' : String(value))
	]);
}

function flowStep(title, meta) {
	return E('div', {'class': 'korobka-flow-step'}, [
		E('div', {'class': 'korobka-flow-title'}, title),
		E('div', {'class': 'korobka-flow-meta'}, meta)
	]);
}

return view.extend({
	load: function() {
		return callStatus();
	},

	handleQr: function(ready, endpoint) {
		const e = endpoint && endpoint.mtg || {};

		if (!ready) {
			ui.showModal(_('QR пока не готов'), [
				E('div', {'class': 'korobka-callout korobka-callout-warn'}, [
					E('div', {'class': 'korobka-callout-icon'}, '!'),
					E('div', {}, [E('strong', {}, _('MTProxy уже работает локально, но внешний endpoint не подтверждён.'))])
				]),
				E('p', {}, [
					_('Причина: '), E('code', {'class': 'korobka-code'}, endpoint && endpoint.reason || 'unknown'),
					E('br'),
					_('Candidate: '), E('code', {'class': 'korobka-code'}, e.candidate_endpoint || '—')
				]),
				E('p', {}, _('После настройки внешнего доступа панель выдаст рабочий Telegram QR. Secret текстом не показывается.')),
				E('div', {'class': 'right'}, [
					E('button', {'class': 'btn korobka-btn', 'click': ui.hideModal}, _('Закрыть')),
					' ',
					E('button', {
						'class': 'btn cbi-button korobka-btn korobka-btn-primary',
						'click': function() { window.location.href = L.url('admin/korobka/access'); }
					}, _('Настроить внешний доступ'))
				])
			]);
			return;
		}

		ui.showModal(_('Telegram MTProxy QR'), [E('p', {'class': 'spinning'}, _('Генерируем access link…'))]);
		return callQr().then(function(res) {
			ui.hideModal();
			if (!res || res.error || !res.svg) {
				notifyError(res && res.error ? res.error : _('QR недоступен'));
				return;
			}
			showSvg(_('Telegram MTProxy'), res.svg);
		}).catch(function(err) {
			ui.hideModal();
			notifyError(String(err));
		});
	},

	render: function(data) {
		const s = data || {};
		const mtg = s.mtg || {};
		const podkop = s.podkop || {};
		const endpoint = s.endpoint || {};
		const e = endpoint.mtg || {};
		const ready = !!e.ready;
		const healthy = !!mtg.running && !!mtg.listening && !!podkop.telegram_socks_ready;

		return E('div', {'class': 'korobka-page'}, [
			css(),
			E('div', {'class': 'korobka-shell'}, [
				E('div', {'class': 'korobka-hero'}, [
					E('div', {}, [
						E('h2', {'class': 'korobka-title'}, _('Telegram MTProxy')),
						E('div', {'class': 'korobka-subtitle'}, _('Отдельный Telegram-тракт: входящий MTG не выходит напрямую в Интернет, а использует локальный SOCKS Podkop и WARP.'))
					]),
					E('span', {'class': 'korobka-badge ' + (healthy ? 'korobka-badge-ok' : 'korobka-badge-warn')}, healthy ? _('Тракт работает') : _('Требует проверки'))
				]),
				E('div', {'class': 'korobka-grid'}, [
					E('div', {'class': 'korobka-card'}, [
						E('div', {'class': 'korobka-card-head'}, [E('h3', {}, _('Состояние')), E('span', {'class': 'korobka-badge ' + (mtg.running ? 'korobka-badge-ok' : 'korobka-badge-warn')}, mtg.running ? _('MTG запущен') : _('MTG остановлен'))]),
						kv(_('TCP порт'), mtg.listen_port, true),
						kv(_('Порт слушается'), mtg.listening ? _('Да') : _('Нет')),
						kv(_('Внутренний SOCKS'), podkop.telegram_socks, true),
						kv(_('SOCKS готов'), podkop.telegram_socks_ready ? _('Да') : _('Нет')),
						kv(_('Исходящий интерфейс'), mtg.outbound || 'awg_warp', true)
					]),
					E('div', {'class': 'korobka-card'}, [
						E('div', {'class': 'korobka-card-head'}, [E('h3', {}, _('Подключение')), E('span', {'class': 'korobka-badge ' + (ready ? 'korobka-badge-ok' : 'korobka-badge-warn')}, ready ? _('QR готов') : _('Нужен endpoint'))]),
					E('p', {'class': 'korobka-subtitle'}, _('Secret и access link не показываются обычным текстом. Для подключения выдаётся только QR авторизованному администратору.')),
					E('div', {'style': 'margin-top:14px'}, [
						E('button', {
							'class': 'btn cbi-button korobka-btn ' + (ready ? 'korobka-btn-primary' : 'korobka-btn-soft'),
							'click': this.handleQr.bind(this, ready, endpoint)
						}, ready ? _('Показать QR') : _('QR / что настроить'))
					])
					])
				]),
				!ready ? E('div', {'class': 'korobka-callout korobka-callout-warn'}, [
					E('div', {'class': 'korobka-callout-icon'}, '!'),
					E('div', {}, [
						E('strong', {}, _('Локальный MTProxy уже готов, но извне его пока нельзя использовать. ')),
						_('Candidate: '), E('code', {'class': 'korobka-code'}, e.candidate_endpoint || '—')
					])
				]) : null,
				E('h3', {'class': 'korobka-section-title'}, _('Маршрут Telegram-трафика')),
				E('div', {'class': 'korobka-flow'}, [
					flowStep(_('Telegram клиент'), 'TCP / ' + String(mtg.listen_port || 8888)),
					flowStep('MTG', _('Входящий прокси')),
					flowStep(_('Podkop SOCKS'), podkop.telegram_socks || '127.0.0.1:4534'),
					flowStep('WARP', mtg.outbound || 'awg_warp')
				])
			])
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
