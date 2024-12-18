const Handler = require('./../handler.js');
const { translateText } = require('./../../utils.js');
let client, socket, entity, connect;

const self = class TabListHandler extends Handler {
	clear() {
		if (this.score.length > 0) {
			client.write('scoreboard_objective', {
				name: 'scoreboard',
				action: 1
			});
			this.score = [];
		}
	}
	roblox(rbSocket) {
		socket = rbSocket;
		socket.on('scoreboard', packet => {
			this.clear();
			client.write('scoreboard_objective', {
				name: 'scoreboard',
				action: 0,
				displayText: translateText(packet.title).slice(0, 40),
				type: 'INTEGER'
			});
			client.write('scoreboard_display_objective', {
				position: 1,
				name: 'scoreboard'
			});

			let index = 0;
			for (const line of packet.content) {
				const name = translateText(line).slice(0, 40);
				this.score.push(name);
				client.write('scoreboard_score', {
					scoreName: 'scoreboard',
					itemName: name,
					action: 0,
					value: packet.content.length - index
				});
				index++;
			}
		});
	}
	minecraft(mcClient) {
		client = mcClient;
	}
	cleanup(requeue) {
		client = requeue ? client : undefined;
		if (client) this.clear();
		this.score = [];
	}
};

module.exports = new self();