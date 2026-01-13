from app.ws.connection_manager import ConnectionManager
from app.services.policy_resolver import PolicyResolver
from app.services.quarantine_handler import QuarantineHandler
from app.services.offline_queue import OfflineQueue
from app.services.ota_manager import OTAManager
from app.services.risk_scorer import RiskScorer
from app.services.eventbus import EventBus

# Shared singletons
manager = ConnectionManager()
policy_resolver = PolicyResolver()
quarantine_handler = QuarantineHandler()
offline_queue = OfflineQueue(max_per_device=200)
ota_manager = OTAManager()
risk_scorer = RiskScorer()
event_bus = EventBus()
