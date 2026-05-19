
# --- LEAVES ---
class LeaveRequestCreate(BaseModel):
    start_date: datetime
    end_date: datetime
    reason: Optional[str] = None
    document_url: Optional[str] = None

class LeaveRequestResponse(BaseModel):
    id: int
    user_id: int
    start_date: datetime
    end_date: datetime
    reason: Optional[str]
    document_url: Optional[str]
    status: str
    
    model_config = ConfigDict(from_attributes=True)

class LeaveBalanceResponse(BaseModel):
    id: int
    year: int
    total_quota: int
    used_quota: int
    
    model_config = ConfigDict(from_attributes=True)

# --- GEOFENCES ---
class GeofenceCreate(BaseModel):
    name: str
    latitude: float
    longitude: float
    radius_meters: float

class GeofenceResponse(BaseModel):
    id: int
    name: str
    radius_meters: float
    
    model_config = ConfigDict(from_attributes=True)
