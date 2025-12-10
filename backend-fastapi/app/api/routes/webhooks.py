from fastapi import APIRouter

router = APIRouter()

@router.post('/webhooks/ping')
async def webhook_ping():
    return {'status': 'ok'}
