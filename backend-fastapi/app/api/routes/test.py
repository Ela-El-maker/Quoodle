from fastapi import APIRouter

router = APIRouter()

@router.get('/test/fault')
async def fault():
    return {'status': 'noop'}
