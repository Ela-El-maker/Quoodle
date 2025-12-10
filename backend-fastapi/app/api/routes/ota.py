from fastapi import APIRouter

router = APIRouter()

@router.get('/ota/check')
async def ota_check():
    return {'status': 'ok'}
