'use strict';
'require rpc';
'require ui';
'require view';

const callStatus = rpc.declare({ object: 'luci.korobka', method: 'status' });
const callAdd = rpc.declare({ object: 'luci.korobka', method: 'add_peer', params: [ 'name' ] });
const callRemove = rpc.declare({ object: 'luci.korobka', method: 'remove_peer', params: [ 'name' ] });
const callQr = rpc.declare({ object: 'luci.korobka', method: 'wg_qr', params: [ 'name' ] });

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

function shortKey(k) {
	if (!k) return '—';
	return k.length > 18 ? k.substring(0, 10) + '…' + k.substring(k.length - 8) : k;
}

function statusBadge(ok) {
	return E('span', {'class': 'korobka-badge ' + (ok ? 'korobka-badge-ok' : 'korobka-badge-warn')}, ok ? _('Активен') : _('Не в runtime'));
}

return view.extend({
	load: function() {
		return callStatus();
	},

	handleAdd: function() {
		const input = document.getElementById('korobka-peer-name');
		const name = input ? input.value.trim() : '';
		ui.showModal(_('Добавление устройства'), [E('p', {'class': 'spinning'}, _('Создаём новую пару ключей и WireGuard peer…'))]);

		return callAdd(name).then(function(res) {
			ui.hideModal();
			if (!res || res.error) {
				notifyError(res && res.error ? res.error : _('Не удалось добавить устройство'));
				return;
			}
			window.location.reload();
		}).catch(function(err) {
			ui.hideModal();
			notifyError(String(err));
		});
	},

	handleRemove: function(name) {
		ui.showModal(_('Удалить устройство?'), [
			E('p', {}, _('Peer будет удалён из WireGuard runtime, UCI и локального хранилища ключей.')),
			E('p', {}, [E('strong', {}, name)]),
			E('div', {'class': 'right'}, [
				E('button', {'class': 'btn korobka-btn', 'click': ui.hideModal}, _('Отмена')),
				' ',
				E('button', {
					'class': 'btn cbi-button korobka-btn korobka-btn-danger',
					'click': function() {
						ui.showModal(_('Удаление устройства'), [E('p', {'class': 'spinning'}, _('Удаляем peer…'))]);
						callRemove(name).then(function(res) {
							ui.hideModal();
							if (!res || res.error) {
								notifyError(res && res.error ? res.error : _('Не удалось удалить устройство'));
								return;
							}
							window.location.reload();
						}).catch(function(err) {
							ui.hideModal();
							notifyError(String(err));
						});
					}
				}, _('Удалить'))
			])
		]);
	},

	handleQr: function(name, ready, endpoint) {
		const wgEndpoint = endpoint && endpoint.wireguard || {};

		if (!ready) {
			ui.showModal(_('QR пока не готов'), [
				E('div', {'class': 'korobka-callout korobka-callout-warn'}, [
					E('div', {'class': 'korobka-callout-icon'}, '!'),
					E('div', {}, [E('strong', {}, _('Устройство создано, но внешний endpoint не подтверждён.'))])
				]),
				E('p', {}, [
					_('Причина: '), E('code', {'class': 'korobka-code'}, endpoint && endpoint.reason || 'unknown'),
					E('br'),
					_('Candidate: '), E('code', {'class': 'korobka-code'}, wgEndpoint.candidate_endpoint || '—')
				]),
				E('p', {}, _('Настройте внешний доступ, после чего этот же peer получит рабочий QR без пересоздания ключей.')),
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

		ui.showModal(_('QR WireGuard'), [E('p', {'class': 'spinning'}, _('Генерируем клиентский конфиг…'))]);
		return callQr(name).then(function(res) {
			ui.hideModal();
			if (!res || res.error || !res.svg) {
				notifyError(res && res.error ? res.error : _('QR недоступен'));
				return;
			}
			showSvg(_('WireGuard — ') + name, res.svg);
		}).catch(function(err) {
			ui.hideModal();
			notifyError(String(err));
		});
	},

	render: function(data) {
		const status = data || {};
		const peers = Array.isArray(status.peers) ? status.peers : [];
		const endpoint = status.endpoint || {};
		const ready = !!(endpoint.wireguard && endpoint.wireguard.ready);

		const rows = peers.map(function(p) {
			return E('tr', {}, [
				E('td', {}, [E('div', {'class': 'korobka-device-name'}, p.name), E('div', {'class': 'korobka-caption'}, _('WireGuard peer'))]),
				E('td', {}, E('code', {'class': 'korobka-code'}, p.address || '—')),
				E('td', {'title': p.public_key || ''}, E('code', {'class': 'korobka-code'}, shortKey(p.public_key))),
				E('td', {}, statusBadge(!!p.runtime)),
				E('td', {}, E('div', {'class': 'korobka-actions'}, [
					E('button', {
						'class': 'btn cbi-button korobka-btn korobka-btn-soft',
						'click': this.handleQr.bind(this, p.name, ready, endpoint)
					}, ready ? _('Показать QR') : _('QR / настройка')),
					E('button', {
						'class': 'btn cbi-button korobka-btn korobka-btn-danger',
						'click': this.handleRemove.bind(this, p.name)
					}, _('Удалить'))
				]))
			]);
		}, this);

		if (!rows.length)
			rows.push(E('tr', {}, [E('td', {'colspan': 5}, _('Устройства ещё не добавлены'))]));

		return E('div', {'class': 'korobka-page'}, [
			css(),
			E('div', {'class': 'korobka-shell'}, [
				E('div', {'class': 'korobka-hero'}, [
					E('div', {}, [
						E('h2', {'class': 'korobka-title'}, _('Устройства WireGuard')),
						E('div', {'class': 'korobka-subtitle'}, _('Каждое устройство получает собственную пару ключей и отдельный адрес. Удаление peer сразу отзывает его доступ.'))
					]),
					E('span', {'class': 'korobka-badge ' + (ready ? 'korobka-badge-ok' : 'korobka-badge-warn')}, ready ? _('QR готовы') : _('Нужен внешний доступ'))
				]),
				!ready ? E('div', {'class': 'korobka-callout korobka-callout-warn'}, [
					E('div', {'class': 'korobka-callout-icon'}, '!'),
					E('div', {}, [
						E('strong', {}, _('QR пока не выдаётся как рабочий конфиг. ')),
						_('Нажатие на «QR / настройка» покажет следующий шаг; сами peers уже созданы и сохраняются.')
					])
				]) : null,
				E('div', {'class': 'korobka-card'}, [
					E('div', {'class': 'korobka-card-head'}, [E('h3', {}, _('Добавить устройство')), E('span', {'class': 'korobka-caption'}, _('Адрес назначится автоматически'))]),
					E('div', {'class': 'korobka-form-row'}, [
						E('input', {
							'id': 'korobka-peer-name',
							'class': 'cbi-input-text korobka-input',
							'placeholder': _('Например: iphone_sergey')
						}),
						E('button', {
							'class': 'btn cbi-button korobka-btn korobka-btn-primary',
							'click': this.handleAdd.bind(this)
						}, _('Добавить устройство'))
					]),
					E('div', {'class': 'korobka-caption', 'style': 'margin-top:8px'}, _('Если имя оставить пустым, будет выбрано следующее свободное phoneN.'))
				]),
				E('h3', {'class': 'korobka-section-title'}, _('Подключённые устройства')),
				E('div', {'class': 'korobka-table-wrap'}, [
					E('table', {'class': 'table korobka-table'}, [
						E('thead', {}, E('tr', {}, [
							E('th', {}, _('Устройство')),
							E('th', {}, _('Адрес')),
							E('th', {}, _('Public key')),
							E('th', {}, _('Состояние')),
							E('th', {}, _('Действия'))
						])),
						E('tbody', {}, rows)
					])
				])
			])
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
