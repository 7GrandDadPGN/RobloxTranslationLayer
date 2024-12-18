const Handler = require('./../handler.js');
const { CLIENT } = require('./../../packets/init.js');
let client, socket, tablist, world;

const self = class EntityHandler extends Handler {
	canSpawn(entity) {
		if (entity.type == -1 && (!tablist.entries[entity.id] && !entity.special)) return false;
		if (!world.isEntityLoaded(entity)) return false;
		return true;
	}
	spawn(entity) {
		if (!entity || entity.spawned) return;
		if (entity.special) {
			tablist.entries[entity.id] = crypto.randomUUID();
			client.write('player_info', {
				action: 0,
				data: [{
					UUID: tablist.entries[entity.id],
					name: 'BOT',
					properties: [],
					gamemode: 1,
					ping: 0
				}]
			});
		}

		entity.spawned = true;
		if (entity.type == -1) {
			client.write('named_entity_spawn', {
				entityId: entity.id,
				playerUUID: tablist.entries[entity.id] ?? crypto.randomUUID(),
				x: entity.pos.x,
				y: entity.pos.y,
				z: entity.pos.z,
				yaw: entity.yaw,
				pitch: 0,
				currentItem: 0,
				metadata: entity.metadata
			});
			client.write('entity_head_rotation', {
				entityId: entity.id,
				headYaw: entity.yaw
			});

			for (const [slot, item] of Object.entries(entity.equipment)) {
				client.write('entity_equipment', {
					entityId: entity.id,
					slot: slot,
					item: item
				});
			}
		} else {
			client.write('spawn_entity', {
				entityId: entity.id,
				type: entity.type,
				x: entity.pos.x,
				y: entity.pos.y,
				z: entity.pos.z,
				yaw: entity.yaw,
				pitch: entity.pitch,
				objectData: {
					intField: 1,
					velocityX: 0,
					velocityY: 0,
					velocityZ: 0
				},
				metadata: entity.metadata
			});
			client.write('entity_metadata', {
				entityId: entity.id,
				metadata: entity.metadata
			});
		}

		if (entity.special) {
			client.write('player_info', {
				action: 4,
				data: [{'UUID': tablist.entries[entity.id]}]
			});
		}

		return true;
	}
	remove(entity) {
		if (!entity || !entity.spawned) return;

		entity.spawned = false;
		client.write('entity_destroy', {
			entityIds: [entity.id]
		});
	}
	respawn() {
		if (!client) return;
		client.write('entity_effect', {
			entityId: this.local.id,
			effectId: 8,
			amplifier: 1,
			duration: 32767,
			hideParticles: false
		});
		client.write('entity_effect', {
			entityId: this.local.id,
			effectId: 4,
			amplifier: -1,
			duration: 32767,
			hideParticles: false
		});
		client.write('update_attributes', {
			entityId: this.local.id,
			properties: [{
				key: 'generic.movementSpeed',
				value: this.local.speed * 0.006,
				modifiers: []
			}]
		});
		client.write('update_health', {
			health: 20,
			food: 19,
			foodSaturation: 0
		});
		this.local.health = {
			health: 20,
			food: 19,
			foodSaturation: 0
		};
	}
	check(entity) {
		if (!entity) return;
		if (this.canSpawn(entity) != entity.spawned) {
			if (entity.spawned) this.remove(entity);
			else this.spawn(entity);
		}
	}
	checkAll() {
		Object.values(this.entities).forEach((entity) => this.check(entity));
	}
	roblox(rbSocket) {
		socket = rbSocket;
		// UNIVERSAL
		socket.on('entity_spawn', packet => {
			const entity = this.entities[packet.id];

			if (entity && entity.spawned) {
				client.write('entity_teleport', {
					entityId: packet.id,
					x: packet.pos.x,
					y: packet.pos.y,
					z: packet.pos.z,
					yaw: packet.yaw,
					pitch: 0,
					onGround: packet.onGround
				});
				client.write('entity_head_rotation', {
					entityId: packet.id,
					headYaw: packet.yaw
				});
			}

			this.entities[packet.id] = {
				id: packet.id,
				type: packet.type,
				special: packet.name && packet.name.includes(' '),
				pos: {x: packet.pos.x, y: packet.pos.y, z: packet.pos.z},
				yaw: packet.yaw,
				pitch: 0,
				metadata: entity ? entity.metadata : {},
				equipment: entity ? entity.equipment : {},
				spawned: entity ? entity.spawned : false,
				name: packet.name
			};

			this.check(this.entities[packet.id]);
		});
		socket.on('lightning', packet => client.write('spawn_entity_weather', packet));
		socket.on('entity_remove', packet => {
			delete this.entities[packet.id];
			client.write('entity_destroy', {
				entityIds: [packet.id]
			});
		});
		socket.on('entity_animation', packet => client.write('animation', packet));
		socket.on('entity_status', packet => client.write('entity_status', packet));
		socket.on('entity_equipment', packet => {
			const entity = this.entities[packet.entityId];
			if (entity) entity.equipment[packet.slot] = packet.item;

			client.write('entity_equipment', packet)
		});
		socket.on('entity_health', packet => {
			const entity = this.entities[packet.id];
			if (entity) entity.metadata[6] = {key: 6, value: packet.hp, type: 3};

			client.write('entity_metadata', {
				entityId: packet.id,
				metadata: [{key: 6, value: packet.hp, type: 3}]
			});
		});
		socket.on('entity_metadata', packet => {
			const entity = this.entities[packet.entityId];
			if (entity) {
				for (const prop of packet.metadata) {
					entity.metadata[prop.key] = prop;
				}
			}
			client.write('entity_metadata', packet);
		});
		socket.on('entity_effect', packet => client.write('entity_effect', packet));
		socket.on('entity_remove_effect', packet => client.write('remove_entity_effect', packet));
		socket.on('entity_move', packet => {
			const entity = this.entities[packet.id];
			if (!entity) {
				console.log('move invalid', packet.id);
				return;
			}
			const lastPos = entity.pos ? {x: entity.pos.x, y: entity.pos.y, z: entity.pos.z} : {x: 0, y: 0, z: 0};
			entity.pos = {x: packet.pos.x, y: packet.pos.y, z: packet.pos.z};
			entity.yaw = packet.yaw;

			client.write('entity_teleport', {
				entityId: entity.id,
				x: entity.pos.x,
				y: entity.pos.y,
				z: entity.pos.z,
				yaw: entity.yaw,
				pitch: 0,
				onGround: packet.onGround
			});
			client.write('entity_head_rotation', {
				entityId: entity.id,
				headYaw: entity.yaw
			});

			if (entity.type != -1) {
				client.write('entity_velocity', {
					entityId: entity.id,
					velocityX: Math.max(Math.min(((packet.pos.x - lastPos.x) / 32) * 8000, 32767), -32768),
					velocityY: Math.max(Math.min(((packet.pos.y - lastPos.y) / 32) * 8000, 32767), -32768),
					velocityZ: Math.max(Math.min(((packet.pos.z - lastPos.z) / 32) * 8000, 32767), -32768)
				})
			}
		});
		socket.on('entity_velocity', packet => client.write('entity_velocity', packet));
		socket.on('collect', packet => client.write('collect', packet));
		socket.on('speed', speed => {
			this.local.speed = speed;
			client.write('update_attributes', {
				entityId: this.local.id,
				properties: [{
					key: 'generic.movementSpeed',
					value: this.local.speed * 0.006,
					modifiers: []
				}]
			});
			socket.emit('health', {food: 2});
			setTimeout(() => socket.emit('health', {food: 19}), 100);
		});
		// LOCAL
		socket.on('health', packet => {
			this.local.health = {
				health: packet.hp ?? this.local.health.health,
				food: packet.food ?? this.local.health.food,
				foodSaturation: packet.foodSaturation ?? this.local.health.foodSaturation
			};
			client.write('update_health', this.local.health);
		});
		socket.on('teleport', packet => client.write('position', packet));
		socket.on('respawn', () => {
			client.write('respawn', {
				dimension: 0,
				difficulty: 2,
				gamemode: 0,
				levelType: 'FLAT'
			});
			this.respawn();
		});
	}
	minecraft(mcClient) {
		client = mcClient;

		// LOGIN
		this.respawn();

		client.on('flying', () => {
			if (!socket) return;
			socket.send(CLIENT.move(this.local));
		});
		client.on('position', ({ x, y, z } = {}) => {
			if (!socket) return;
			this.local.pos = {x: (x * 3) - 1.5, y: (y * 3) + 1.587, z: (z * 3) - 1.5};
			socket.send(CLIENT.move(this.local));
		});
		client.on('look', ({ yaw, pitch } = {}) => {
			if (!socket) return;
			this.local.yaw = (yaw * -1) - 180;
			this.local.pitch = (pitch * -1);
			socket.send(CLIENT.move(this.local));
		});
		client.on('position_look', ({ x, y, z, onGround, yaw, pitch } = {}) => {
			if (!socket) return;
			this.local.pos = {x: (x * 3) - 1.5, y: (y * 3) + 1.587, z: (z * 3) - 1.5};
			this.local.yaw = (yaw * -1) - 180;
			this.local.pitch = (pitch * -1);
			socket.send(CLIENT.move(this.local));
		});
		client.on('use_entity', packet => {
			if (packet.target != undefined && this.entities[packet.target] && packet.mouse == 1) {
				socket.send(CLIENT.attack(packet.target));
			}
		});
		client.on('held_item_slot', packet => socket.send(CLIENT.switch_slot(packet.slotId)));
		client.on('arm_animation', () => socket.send(CLIENT.swing(true)));
	}
	cleanup(requeue) {
		client = requeue ? client : undefined;
		socket = requeue ? socket : undefined;
		this.entities = {};
		this.skins = {};
		this.gamemodes = {};
		this.local = {
			id: 99999,
			speed: 20,
			pos: {x: 0, y: 0, z: 0},
			state: [],
			lastState: [],
			health: {hp: 20, food: 4, foodSaturation: 4},
		};
	}
	obtainHandlers(handlers) {
		tablist = handlers.tablist;
		world = handlers.world;
	}
};

module.exports = new self();