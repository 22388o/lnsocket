
CFLAGS=-Wall -Os -Ideps/secp256k1/include -Ideps/libsodium/src/libsodium/include -Ideps
LDFLAGS=

SUBMODULES=deps/secp256k1

# Build for the simulator
XCODEDIR=$(shell xcode-select -p)
SIM_SDK=$(XCODEDIR)/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk
IOS_SDK=$(XCODEDIR)/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk

HEADERS=config.h deps/secp256k1/include/secp256k1.h deps/libsodium/src/libsodium/include/sodium/crypto_aead_chacha20poly1305.h
ARS=libsecp256k1.a libsodium.a
WASM_ARS=target/wasm/libsecp256k1.a target/wasm/libsodium.a target/wasm/lnsocket.a
OBJS=sha256.o hkdf.o hmac.o sha512.o lnsocket.o error.o handshake.o crypto.o bigsize.o commando.o bech32.o
ARM64_OBJS=$(OBJS:.o=-arm64.o)
X86_64_OBJS=$(OBJS:.o=-x86_64.o)
WASM_OBJS=$(OBJS:.o=-wasm.o) lnsocket_wasm-wasm.o
BINS=test lnrpc

DEPS=$(OBJS) $(ARS) $(HEADERS)

all: $(BINS) lnsocket.a

ios: target/ios/lnsocket.a target/ios/libsodium.a target/ios/libsecp256k1.a

wasm: target/wasm/lnsocket.js target/wasm/lnsocket.wasm

target/wasm/lnsocket.js: target/tmp/lnsocket.js lnsocket_lib.js
	cat $^ > $@

libsodium-1.0.18-stable.tar.gz:
	wget https://download.libsodium.org/libsodium/releases/libsodium-1.0.18-stable.tar.gz

deps/libsodium/configure: libsodium-1.0.18-stable.tar.gz
	tar xvf $^; \
	mkdir -p deps; \
	mv libsodium-stable deps/libsodium

deps/secp256k1/.git:
	@tools/refresh-submodules.sh $(SUBMODULES)

lnsocket.a: $(OBJS)
	ar rcs $@ $(OBJS)

target/arm64/lnsocket.a: $(ARM64_OBJS)
	@mkdir -p target/arm64
	ar rcs $@ $^

target/x86_64/lnsocket.a: $(X86_64_OBJS)
	@mkdir -p target/x86_64
	ar rcs $@ $^

target/wasm/lnsocket.a: $(WASM_OBJS)
	@mkdir -p target/wasm
	emar rcs $@ $^

target/ios/lnsocket.a: target/x86_64/lnsocket.a target/arm64/lnsocket.a
	@mkdir -p target/ios
	lipo -create $^ -output $@

%-arm64.o: %.c config.h
	@echo "cc $@"
	@$(CC) $(CFLAGS) -c $< -o $@ -arch arm64 -isysroot $(IOS_SDK) -target arm64-apple-ios -fembed-bitcode

%-wasm.o: %.c config.h
	@echo "emcc $@"
	@emcc $(CFLAGS) -c $< -o $@

%-x86_64.o: %.c config.h
	@echo "cc $@"
	@$(CC) $(CFLAGS) -c $< -o $@ -arch x86_64 -isysroot $(SIM_SDK) -mios-simulator-version-min=6.0.0 -target x86_64-apple-ios-simulator

# TODO cross compiled config??
config.h: configurator
	./configurator > $@

configurator: configurator.c
	$(CC) $< -o $@

%.o: %.c $(HEADERS)
	@echo "cc $@"
	@$(CC) $(CFLAGS) -c $< -o $@

deps/secp256k1/include/secp256k1.h: deps/secp256k1/.git

deps/libsodium/src/libsodium/include/sodium/crypto_aead_chacha20poly1305.h: deps/libsodium/configure

deps/secp256k1/config.log: deps/secp256k1/configure
	cd deps/secp256k1; \
	./configure --disable-shared --enable-module-ecdh

deps/libsodium/config.status: deps/libsodium/configure
	cd deps/libsodium; \
	./configure --disable-shared --enable-minimal

deps/secp256k1/configure: deps/secp256k1/.git
	cd deps/secp256k1; \
	patch -p1 < ../../tools/0001-configure-customizable-AR-and-RANLIB.patch; \
	./autogen.sh

deps/libsodium/config.log: deps/libsodium/configure
	cd deps/libsodium; \
	./configure

deps/secp256k1/.libs/libsecp256k1.a: deps/secp256k1/config.log
	cd deps/secp256k1; \
	make -j libsecp256k1.la

libsecp256k1.a: deps/secp256k1/.libs/libsecp256k1.a
	cp $< $@

libsodium.a: deps/libsodium/src/libsodium/.libs/libsodium.a
	cp $< $@

target/ios/libsodium.a: deps/libsodium/libsodium-ios/lib/libsodium.a
	@mkdir -p target/ios
	cp $< $@

target/ios/libsecp256k1.a: deps/secp256k1/libsecp256k1-ios/lib/libsecp256k1.a
	@mkdir -p target/ios
	cp $< $@

target/wasm/libsecp256k1.a: deps/secp256k1/libsecp256k1-wasm/lib/libsecp256k1.a
	@mkdir -p target/wasm
	cp $< $@

target/wasm/libsodium.a: deps/libsodium/libsodium-js/lib/libsodium.a
	@mkdir -p target/wasm
	cp $< $@

deps/libsodium/libsodium-ios/lib/libsodium.a: deps/libsodium/configure
	cd deps/libsodium; \
	./dist-build/ios.sh

deps/secp256k1/libsecp256k1-ios/lib/libsecp256k1.a: deps/secp256k1/configure
	./tools/secp-ios.sh

deps/secp256k1/libsecp256k1-wasm/lib/libsecp256k1.a: deps/secp256k1/configure
	./tools/secp-wasm.sh

deps/libsodium/libsodium-js/lib/libsodium.a: deps/libsodium/configure
	cd deps/libsodium; \
	./dist-build/emscripten.sh --standard

deps/libsodium/src/libsodium/.libs/libsodium.a: deps/libsodium/config.log
	cd deps/libsodium/src/libsodium; \
	make -j libsodium.la

check: test
	@./test

test: test.o $(DEPS)
	@echo "ld test"
	@$(CC) $(CFLAGS) test.o $(OBJS) $(ARS) $(LDFLAGS) -o $@

lnrpc: lnrpc.o $(DEPS)
	@echo "ld lnrpc"
	@$(CC) $(CFLAGS) lnrpc.o $(OBJS) $(ARS) $(LDFLAGS) -o $@

target/wasm/lnsocket.wasm: target/tmp/lnsocket.js
	cp target/tmp/lnsocket.wasm target/wasm/lnsocket.wasm

target/tmp/lnsocket.js: $(WASM_ARS) lnsocket_pre.js
	@mkdir -p target/tmp
	emcc --pre-js lnsocket_pre.js -s ENVIRONMENT=web -s MODULARIZE -flto -s 'EXPORTED_FUNCTIONS=["_malloc", "_free"]' -s EXPORTED_RUNTIME_METHODS=ccall,cwrap $(CFLAGS) -Wl,-whole-archive $(WASM_ARS) -Wl,-no-whole-archive -o target/tmp/lnsocket.js

tags: fake
	find . -name '*.c' -or -name '*.h' | xargs ctags

clean: fake
	rm -rf $(BINS) config.h $(OBJS) $(ARM64_OBJS) $(X86_64_OBJS) $(WASM_OBJS) target

distclean: clean
	rm -rf $(ARS) deps target


.PHONY: fake
