all    :; forge build
clean  :; forge clean
test   :; ./test.sh $(match)
deploy :; make && forge create Sequencer
