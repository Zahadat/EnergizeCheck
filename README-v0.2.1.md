# EnergizeCheck v0.2.1 - Plant Structure Import Fix

Plant Structure now maps generic hierarchical assets using AssetType, AssetCode and ParentAssetCode.

Current limitation: AssetCode must remain project-wide unique in v0.2.1. A later schema revision will add hierarchical local-code identity so labels such as MPPT-01 may repeat under different inverters safely.
