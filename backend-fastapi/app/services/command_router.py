class CommandRouter:
    async def route(self, command: dict) -> dict:
        return {"status": "accepted", "command": command}
