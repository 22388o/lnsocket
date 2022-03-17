
const Module = require("./dist/node/lnsocket.js")
const LNSocketReady = Module.lnsocket_init()

async function load_lnsocket(opts)
{
	const LNSocket = await LNSocketReady
	return LNSocket
}

module.exports = load_lnsocket
