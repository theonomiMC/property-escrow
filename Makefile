.PHONY: help deploy-impl upgrade test coverage tag-release

help:
	@echo "PropertyEscrow Contract Management"
	@echo "=================================="
	@echo "make test              - Run tests (excluding invariants for speed)"
	@echo "make coverage          - Generate coverage report (excluding invariants)"
	@echo "make deploy-impl       - Deploy new implementation to Sepolia"
	@echo "make upgrade           - Upgrade proxy via Upgrade script"
	@echo "make tag-release       - Create and push release tag"

test:
	forge test --no-match-contract "PropertyEscrowInvariant" -vvv

coverage:
	forge coverage --no-match-contract "PropertyEscrowInvariant" --report lcov
	genhtml lcov.info --output-directory coverage-html
	@echo "Coverage HTML generated in ./coverage-html folder"

deploy-impl:
	@echo "Deploying new implementation to Sepolia..."
	forge script script/PropertyEscrow.s.sol:DeployPropertyEscrow \
		--rpc-url $$SEPOLIA_RPC_URL \
		--broadcast \
		--verify \
		-vvvv

upgrade:
	@echo "Upgrading proxy to new implementation and verifying..."
	forge script script/UpgradePropertyEscrow.s.sol:UpgradePropertyEscrow \
		--rpc-url $$SEPOLIA_RPC_URL \
		--broadcast \
		--verify \
		-vvvv

tag-release:
	@read -p "Enter version (e.g., v1.0.2): " VERSION; \
	read -p "Enter release message: " MESSAGE; \
	git tag -a $$VERSION -m "$$MESSAGE"; \
	git push origin $$VERSION; \
	echo "Tag $$VERSION created and pushed successfully."