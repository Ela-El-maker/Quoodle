from fastapi import APIRouter

router = APIRouter()

@router.get('/admin/ping')
async def admin_ping():
    return {'status': 'ok'}
