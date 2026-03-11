UNAME_S := $(shell uname -s)

run-sequential:
	gcc sequential.c -o nqueen-sequential
	./nqueen-sequential

run-parallel:
ifeq ($(UNAME_S),Darwin)
	@echo "Detected macOS..."
	chmod +x benchmark.macos.sh
	./benchmark.macos.sh
else ifeq ($(UNAME_S),Linux)
	@echo "Detected Linux..."
	chmod +x benchmark.linux.sh
	./benchmark.linux.sh
else
	@echo "Unsupported OS: $(UNAME_S)"
endif