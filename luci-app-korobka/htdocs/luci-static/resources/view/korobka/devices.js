'use strict';
'require rpc';
'require ui';
'require view';

const callStatus = rpc.declare({ object: 'luci.korobka', method: 'status' });
const callAdd = rpc.declare({ object: 'luci.korobka', method: 'add_peer', params: [ 'name' ] });
const callRemove = rpc.declare({ object: 'luci.korobka', method: 'remove_peer', params: [ 'name' ] });
const callQr = rpc.declare({ object: 'luci.korobka', method: 'wg_qr', params: [ 'name' ] });

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

function shortKey(k) {
	if (!k) return '—';
	return k.length > 18 ? k.substring(0, 10) + '…' + k.substring(k.length - 8) : k;
}

return view.extend({
	load: function() {
		/* status already contains peers; avoid a second RPC/process on page load */
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
			E('p', {}, _('Peer будет удалён из runtime WireGuard, UCI и локального хранилища ключей.')),
			E('p', {}, [E('strong', {}, name)]),
			E('div', {'class': 'right'}, [
				E('button', {'class': 'btn', 'click': ui.hideModal}, _('Отмена')),
				' ',
				E('button', {
					'class': 'btn cbi-button cbi-button-negative',
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
				E('p', {}, _('WireGuard peer уже создан, но внешний endpoint ещё не подтверждён.')),
				E('p', {}, [
					_('Причина: '), E('code', {}, endpoint && endpoint.reason || 'unknown'),
					E('br'),
					_('Candidate: '), E('code', {}, wgEndpoint.candidate_endpoint || '—')
				]),
				E('p', {}, _('Настройте внешний доступ, после чего QR станет рабочим.')),
				E('div', {'class': 'right'}, [
					E('button', {'class': 'btn', 'click': ui.hideModal}, _('Закрыть')),
					' ',
					E('button', {
						'class': 'btn cbi-button cbi-button-action',
						'click': function() { window.location.href = L.url('admin/korobka/access'); }
					}, _('Внешний доступ'))
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

		const table = E('table', {'class': 'table'}, [
			E('tr', {'class': 'tr table-titles'}, [
				E('th', {'class': 'th'}, _('Устройство')),
				E('th', {'class': 'th'}, _('Адрес')),
				E('th', {'class': 'th'}, _('Public key')),
				E('th', {'class': 'th'}, _('Runtime')),
				E('th', {'class': 'th'}, _('Действия'))
			])
		]);

		peers.forEach(function(p) {
			const actions = E('div', {}, [
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'title': ready ? _('Показать QR') : _('Показать, что нужно для активации QR'),
					'click': this.handleQr.bind(this, p.name, ready, endpoint)
				}, ready ? _('QR') : _('QR / настройка')),
				' ',
				E('button', {
					'class': 'btn cbi-button cbi-button-negative',
					'click': this.handleRemove.bind(this, p.name)
				}, _('Удалить'))
			]);

			table.appendChild(E('tr', {'class': 'tr'}, [
				E('td', {'class': 'td'}, [E('strong', {}, p.name)]),
				E('td', {'class': 'td'}, E('code', {}, p.address || '—')),
				E('td', {'class': 'td', 'title': p.public_key || ''}, E('code', {}, shortKey(p.public_key))),
				E('td', {'class': 'td'}, p.runtime ? _('Активен') : _('Нет в runtime')),
				E('td', {'class': 'td'}, actions)
			]));
		}, this);

		if (!peers.length)
			table.appendChild(E('tr', {'class': 'tr'}, [E('td', {'class': 'td', 'colspan': 5}, _('Устройства ещё не добавлены'))]));

		const nodes = [
			E('h2', {}, _('Устройства WireGuard')),
			E('p', {}, _('Каждое устройство получает собственную новую пару ключей и отдельный адрес 10.77.0.x/32.'))
		];

		if (!ready) {
			nodes.push(E('div', {'class': 'cbi-section warning'}, [
				E('strong', {}, _('Внешний endpoint ещё не готов. ')),
				_('QR-кнопки доступны для объяснения следующего шага; рабочий QR будет выдан после настройки внешнего доступа.')
			]));
		}

		nodes.push(E('div', {'class': 'cbi-section'}, [
			E('h3', {}, _('Добавить устройство')),
			E('div', {'style': 'display:flex;gap:8px;align-items:center;flex-wrap:wrap'}, [
				E('input', {
					'id': 'korobka-peer-name',
					'class': 'cbi-input-text',
					'placeholder': _('Имя, например iphone_sergey'),
					'style': 'min-width:260px'
				}),
				E('button', {
					'class': 'btn cbi-button cbi-button-add',
					'click': this.handleAdd.bind(this)
				}, _('Добавить'))
			]),
			E('p', {'class': 'description'}, _('Если имя оставить пустым, будет выбрано следующее свободное phoneN.'))
		]));

		nodes.push(E('div', {'class': 'cbi-section'}, [E('h3', {}, _('Список устройств')), table]));
		return E('div', {}, nodes);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
