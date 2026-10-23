from datetime import datetime, timezone
from typing import Literal
from uuid import UUID
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

Status = Literal["todo", "inProgress", "done", "backlog"]
Priority = Literal["none", "low", "medium", "high"]
MAX_SQLITE_INTEGER = 2**63 - 1


def utc_instant(value: str) -> str:
    """A fixed-width UTC key, including all six fractional digits, for exact ordering."""
    return datetime.fromisoformat(value).astimezone(timezone.utc).isoformat(timespec='microseconds')


def timestamp() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


class Patch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str | None = Field(default=None, max_length=2000)
    notes: str | None = Field(default=None, max_length=100_000)
    status: Status | None = None
    priority: Priority | None = None
    dueAt: datetime | None = None

    @field_validator("title")
    @classmethod
    def title_not_empty(cls, value):
        if value is None or not (value := " ".join(value.split())):
            raise ValueError("title must not be empty")
        return value

    @field_validator("status", "priority")
    @classmethod
    def required_when_present(cls, value):
        if value is None:
            raise ValueError("status and priority cannot be null")
        return value

    @field_validator("dueAt")
    @classmethod
    def timezone_required(cls, value):
        if value is not None:
            if value.tzinfo is None:
                raise ValueError("dueAt requires a timezone")
            return value.astimezone(timezone.utc)
        return value


class Mutation(BaseModel):
    model_config = ConfigDict(extra="forbid")
    mutationId: UUID
    taskId: UUID
    baseVersion: int = Field(ge=0, le=MAX_SQLITE_INTEGER)
    kind: Literal["create", "update", "delete"]
    patch: Patch = Field(default_factory=Patch)

    @model_validator(mode="after")
    def valid_operation(self):
        if self.kind == "create" and not self.patch.title:
            raise ValueError("create requires title")
        if self.kind == "create" and self.baseVersion != 0:
            raise ValueError("create requires baseVersion 0")
        if self.kind == "delete" and self.patch.model_fields_set:
            raise ValueError("delete has no patch")
        if self.kind == "update" and not self.patch.model_fields_set:
            raise ValueError("update requires a patch")
        return self
