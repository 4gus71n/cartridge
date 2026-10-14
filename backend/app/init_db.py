from . import models  # noqa: F401  (register models)
from .db import Base, engine


def main() -> None:
    Base.metadata.create_all(bind=engine)
    print("Tables created.")


if __name__ == "__main__":
    main()
