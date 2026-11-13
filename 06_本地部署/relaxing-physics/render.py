"""Compatibility launcher; implementation lives in the separated src layers."""
from src.cli import main

if __name__ == '__main__':
    raise SystemExit(main())
