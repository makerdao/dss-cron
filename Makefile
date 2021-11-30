all    :; DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=200 dapp --use solc:0.8.9 build
clean  :; dapp clean
test   :; ./test.sh $(match)
deploy :; make && dapp create Sequencer
