'use strict';
'require rpc';
'require ui';
'require view';

const callStatus = rpc.declare({ object: 'luci.korobka', method: 'status' });
const callQr = rpc.declare({ object: 'luci.korobka', method: 'mtg_qr' });

function notifyError(message) {
	ui.addNotification(null, E('p', {}, message || _('Неизвестная ошибка')), 'error');
}

function showSvg(title, svg) {
	const box = E('div', {'style': 'text-align:center;max-width:460px;margin:auto'});
	box.innerHTML = svg;
	ui.showModal(title, [
		box,
		E('div', {'class': 'right', 'style': 'margin-top:16px'}, [
			E('button', {'class': 'btn cbi-button', 'click': ui.hideModal}, _('Закрыть'))
		])
	]);
}

function kv(label, value) {
	return E('div', {'style': 'display:flex;justify-content:space-between;gap:16px;margin:8px 0'}, [
		E('span', {'style': 'color:#666'}, label),
		E('strong', {'style': 'text-align:right'}, value == null || value === '' ? '—' : String(value))
	]);
}

return view.extend({
	load: function() {
		return callStatus();
	},

	handleQr: function() {
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

		const nodes = [
			E('h2', {}, _('Telegram MTProxy')),
			E('p', {}, _('Отдельный Telegram-тракт Коробки. MTG не выходит напрямую: весь его исходящий трафик идёт через локальный SOCKS Podkop и WARP.')),
			E('div', {'class': 'cbi-section'}, [
				E('h3', {}, _('Состояние')),
				kv(_('MTG'), mtg.running ? _('Работает') : _('Не работает')),
				kv(_('TCP порт'), mtg.listen_port),
				kv(_('Порт слушается'), mtg.listening ? _('Да') : _('Нет')),
				kv(_('Внутренний SOCKS'), podkop.telegram_socks),
				kv(_('SOCKS готов'), podkop.telegram_socks_ready ? _('Да') : _('Нет')),
				kv(_('Исходящий интерфейс'), mtg.outbound || 'awg_warp')
			]),
			E('div', {'class': 'cbi-section'}, [
				E('h3', {}, _('Маршрут')),
				E('pre', {'style': 'white-space:pre-wrap'}, 'Telegram client\n  ↓ TCP/8888\nMTG\n  ↓\n127.0.0.1:4534\n  ↓\nPodkop TelegramProxy-out\n  ↓\nawg_warp\n  ↓\nTelegram')
			])
		];

		if (!ready) {
			nodes.push(E('div', {'class': 'cbi-section warning'}, [
				E('strong', {}, _('QR пока недоступен. ')),
				_('Endpoint не готов: '), E('code', {}, endpoint.reason || 'unknown'),
				E('br'),
				_('Candidate: '), E('code', {}, e.candidate_endpoint || '—')
			]));
		}

		nodes.push(E('div', {'class': 'cbi-section'}, [
			E('h3', {}, _('Подключение Telegram')),
			E('p', {}, _('Secret и ссылка не показываются обычным текстом. Панель выдаёт только QR для авторизованного администратора.')),
			E('button', {
				'class': 'btn cbi-button cbi-button-action',
				'disabled': ready ? null : 'disabled',
				'click': this.handleQr.bind(this)
			}, _('Показать QR'))
		]));

		return E('div', {}, nodes);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
