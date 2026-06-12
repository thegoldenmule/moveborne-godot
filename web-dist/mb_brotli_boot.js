// mb_brotli_boot.js — host-agnostic brotli decompression for the Moveborne web build.
//
// Why this exists: AWS Amplify (and most "dumb" static hosts) will NOT serve a
// `Content-Encoding: br` response for our big .wasm/.pck — Amplify treats
// Content-Encoding as a read-only header and rejects it, and CloudFront's
// auto-compression skips `application/wasm` and anything over 10 MB. So instead
// of relying on transport compression, we ship `index.wasm.br` / `index.pck.br`
// and decompress them in the browser before handing the bytes to the engine.
//
// Mechanism: install a `window.fetch` wrapper BEFORE Godot's `index.js` runs
// (this file is a classic <script> in <head>, so it executes first). When the
// engine asks for `index.wasm` or `index.pck`, we transparently fetch the `.br`
// sibling, brotli-decompress it, and return a synthetic Response carrying the
// original (decompressed) bytes. Godot's loader is never patched, so this
// survives engine upgrades.
(function () {
	'use strict';

	// Only these exact same-origin asset paths are redirected to a `.br` sibling.
	// Everything else — including the game's own in-engine GodotFetch/HTTPClient
	// requests — passes straight through untouched.
	var TARGETS = ['index.wasm', 'index.pck'];

	// Kick off decoder load immediately (parallel with the engine bootstrap).
	// `brotli_dec_wasm.js` is the wasm-bindgen "web" build: default export is the
	// async init, `decompress(Uint8Array) -> Uint8Array` is the one-shot decode.
	var decoderReady = import('./brotli_dec_wasm.js').then(function (mod) {
		return mod.default(new URL('./brotli_dec_wasm_bg.wasm', document.baseURI)).then(function () {
			return mod.decompress;
		});
	});

	var nativeFetch = window.fetch.bind(window);

	function targetFor(input) {
		var raw = (typeof input === 'string') ? input
			: (input && typeof input.url === 'string') ? input.url
				: null;
		if (raw == null) {
			return null;
		}
		var path;
		try {
			path = new URL(raw, document.baseURI);
		} catch (e) {
			return null;
		}
		if (path.origin !== window.location.origin) {
			return null; // never touch cross-origin requests
		}
		for (var i = 0; i < TARGETS.length; i++) {
			if (path.pathname.endsWith('/' + TARGETS[i]) || path.pathname === '/' + TARGETS[i]) {
				return { url: path.href, name: TARGETS[i] };
			}
		}
		return null;
	}

	window.fetch = function (input, init) {
		var hit = targetFor(input);
		if (hit == null) {
			return nativeFetch(input, init);
		}
		var contentType = hit.name.endsWith('.wasm') ? 'application/wasm' : 'application/octet-stream';
		// Fetch the precompressed sibling through the *native* fetch (no recursion).
		var compressed = nativeFetch(hit.url + '.br', { credentials: 'same-origin' });
		return Promise.all([decoderReady, compressed]).then(function (parts) {
			var decompress = parts[0];
			var resp = parts[1];
			if (!resp.ok) {
				return resp; // surface the network error to the engine's loader
			}
			return resp.arrayBuffer().then(function (buf) {
				var out = decompress(new Uint8Array(buf));
				return new Response(out, {
					status: 200,
					statusText: 'OK',
					headers: {
						'Content-Type': contentType,
						'Content-Length': String(out.byteLength),
					},
				});
			});
		});
	};
})();
