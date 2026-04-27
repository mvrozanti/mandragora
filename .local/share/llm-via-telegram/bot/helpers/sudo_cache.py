"""In-memory sudo password cache with TTL expiry."""

import logging
import time

import config

logger = logging.getLogger(__name__)


class SudoCache:
    """Singleton-style cache that holds the sudo password for a limited time."""

    _password: str | None = None
    _expiry: float = 0.0

    @classmethod
    def get(cls) -> str | None:
        """Return the cached password if still valid, else None."""
        if cls._password and time.time() < cls._expiry:
            return cls._password
        if cls._password and time.time() >= cls._expiry:
            logger.info("Sudo cache expired")
            cls._password = None
        return None

    @classmethod
    def set(cls, password: str) -> None:
        """Store the password with a TTL."""
        cls._password = password
        cls._expiry = time.time() + config.SUDO_CACHE_TIMEOUT
        logger.debug("Sudo password cached for %ds", config.SUDO_CACHE_TIMEOUT)

    @classmethod
    def clear(cls) -> None:
        """Clear the cached password."""
        cls._password = None
        logger.debug("Sudo cache cleared")

    @classmethod
    def is_waiting(cls) -> bool:
        """Check if we're in a state of waiting for the user to provide the password."""
        return cls._password is None
