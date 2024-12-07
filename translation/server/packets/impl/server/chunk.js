const Packet = require('./../../packet.js');
const CHUNK_SIZE = 16 * 16 * 16;

const self = class chunk extends Packet {
	name = 'chunk'
	decode(data) {
		const paletteSize = data.readUint8(10);
		let chunk = {cells: [], palette: [], x: data.readInt32LE(1), z : data.readInt32LE(5)};

		if (paletteSize > 0) {
			for (let i = 0; i <= paletteSize; i++) {
				const start = 11 + (i * 2);
				chunk.palette.push(data.readUint16LE(start));
			}
		}

		for (let i = 0; i < data.readUint8(9); i++) {
			const start = 11 + (paletteSize * 2) + (i * (CHUNK_SIZE + 1));
			chunk.cells.push({y: data.readUint8(start), bitArray: new Uint8Array(data.buffer, data.byteOffset + start + 1, CHUNK_SIZE)});
		}

		return chunk;
	}
};

module.exports = new self();