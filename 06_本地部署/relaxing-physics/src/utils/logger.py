"""Date-rotated standard logger for the local studio."""

import logging
import os
from datetime import datetime

from .paths import LOG_DIR, ensure_directories


def get_logger(name: str) -> logging.Logger:
    """Return a configured logger without installing duplicate handlers."""
    ensure_directories()
    logger = logging.getLogger(name)
    if logger.handlers:
        return logger
    logger.setLevel(os.getenv("LOG_LEVEL", "INFO").upper())
    path = LOG_DIR / f"{datetime.now():%Y-%m-%d}.log"
    handler = logging.FileHandler(path, encoding="utf-8")
    handler.setFormatter(logging.Formatter("[%(asctime)s] [%(levelname)-5s] [%(name)s] %(message)s"))
    logger.addHandler(handler)
    console = logging.StreamHandler()
    console.setFormatter(logging.Formatter("[%(levelname)-5s] %(message)s"))
    logger.addHandler(console)
    logger.propagate = False
    return logger
