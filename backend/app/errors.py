class APIError(Exception):
    """Only this safe, public message is returned to callers."""

    def __init__(self, status: int, code: str, message: str):
        self.status = status
        self.code = code
        self.message = message
        super().__init__(code)
