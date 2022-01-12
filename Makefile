all    :; forge build --optimize
clean  :; forge clean
test   :; ./test.sh $(match)
deploy :; make && forge create Sequencer
