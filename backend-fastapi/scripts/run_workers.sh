#!/usr/bin/env bash
python - <<'PY'
import asyncio
async def main():
    await asyncio.sleep(0.1)
if __name__ == '__main__':
    asyncio.run(main())
PY
