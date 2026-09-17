.PHONY: help check

help:
	@printf '%s\n' 'Curso Kubernetes: comece pelo README.md.' 'make check: verifica conteúdo offline (Python 3 + PyYAML); não acessa cluster/AWS.'

check:
	python3 -m unittest discover -s scripts -p 'test_*.py'
	python3 scripts/verificar-curso.py
