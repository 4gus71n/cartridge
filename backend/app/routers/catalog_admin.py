from fastapi import APIRouter, Depends

from .. import catalog
from ..models import User
from ..security import get_admin_user

router = APIRouter(tags=["admin"])


@router.post("/admin/catalog/sync")
def sync_catalog(_: User = Depends(get_admin_user)):
    """Pull the originals index from Pages and republish catalog.json now."""
    return catalog.sync_and_publish("admin sync")
