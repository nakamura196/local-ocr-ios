"""Create the three tip products (consumable IAPs) on the App Store Connect record "Local OCR".

Same tiers, prices and texts as KotenOCR. Safe to run again: products that already exist are skipped
(their texts, price and availability are filled in only where missing).

Uses KotenOCR's API key (~/git/hi/miyako/koten-ocr-ios/.env, ~/.private_keys/AuthKey_<KEY_ID>.p8).

    python3 scripts/asc_tips.py
"""
import importlib.util
import json
import urllib.error
import urllib.parse
import urllib.request

APP_ID = "6829376468"  # Local OCR (macOS + iOS, universal purchase)
TIERS = [
    ("com.nakamura.localocr.tip.small", "Small Tip", "0.99",
     {"ja": ("小さな応援", "開発を応援する小さなチップ"), "en-US": ("Small Tip", "A small tip to support development")}),
    ("com.nakamura.localocr.tip.medium", "Medium Tip", "2.99",
     {"ja": ("応援", "開発を応援するチップ"), "en-US": ("Medium Tip", "A tip to support development")}),
    ("com.nakamura.localocr.tip.large", "Large Tip", "6.99",
     {"ja": ("大きな応援", "開発を大きく応援するチップ"), "en-US": ("Large Tip", "A generous tip to support development")}),
]

_spec = importlib.util.spec_from_file_location(
    "kotenasc", "/Users/nakamura/git/hi/miyako/koten-ocr-ios/scripts/upload_screenshots.py")
_asc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_asc)


def call(method, path, body=None):
    req = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, method=method,
                                 data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": "Bearer " + _asc.generate_token(),
                                          "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r) if r.status != 204 else {}
    except urllib.error.HTTPError as e:
        raise SystemExit(f"{method} {path} -> {e.code}\n{e.read().decode()}")


def all_pages(path):
    out = []
    while path:
        r = call("GET", path)
        out += r["data"]
        nxt = r.get("links", {}).get("next")
        path = nxt.replace("https://api.appstoreconnect.apple.com", "") if nxt else None
    return out


def main():
    existing = {d["attributes"]["productId"]: d["id"]
                for d in all_pages(f"/v1/apps/{APP_ID}/inAppPurchasesV2?limit=200")}
    territories = [t["id"] for t in all_pages("/v1/territories?limit=200")]

    for product_id, ref_name, price, locs in TIERS:
        iap_id = existing.get(product_id)
        if iap_id:
            print(f"{product_id}: exists ({iap_id})")
        else:
            r = call("POST", "/v2/inAppPurchases", {"data": {
                "type": "inAppPurchases",
                "attributes": {"name": ref_name, "productId": product_id,
                               "inAppPurchaseType": "CONSUMABLE", "familySharable": False},
                "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}}})
            iap_id = r["data"]["id"]
            print(f"{product_id}: created ({iap_id})")

        have = {d["attributes"]["locale"] for d in call("GET", f"/v2/inAppPurchases/{iap_id}/inAppPurchaseLocalizations")["data"]}
        for locale, (name, desc) in locs.items():
            if locale in have:
                continue
            call("POST", "/v1/inAppPurchaseLocalizations", {"data": {
                "type": "inAppPurchaseLocalizations",
                "attributes": {"locale": locale, "name": name, "description": desc},
                "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}}}})
            print(f"  localization {locale}: {name}")

        q = urllib.parse.urlencode({"filter[territory]": "USA", "limit": 200})
        points = all_pages(f"/v2/inAppPurchases/{iap_id}/pricePoints?{q}")
        point = next(p for p in points if p["attributes"]["customerPrice"] == price)
        call("POST", "/v1/inAppPurchasePriceSchedules", {
            "data": {"type": "inAppPurchasePriceSchedules", "relationships": {
                "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${price0}"}]}}},
            "included": [{"type": "inAppPurchasePrices", "id": "${price0}",
                          "attributes": {"startDate": None},
                          "relationships": {"inAppPurchasePricePoint": {
                              "data": {"type": "inAppPurchasePricePoints", "id": point["id"]}}}}]})
        print(f"  price: USD {price} (base USA, other territories auto-equalized)")

        call("POST", "/v1/inAppPurchaseAvailabilities", {"data": {
            "type": "inAppPurchaseAvailabilities",
            "attributes": {"availableInNewTerritories": True},
            "relationships": {
                "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories]}}}})
        print(f"  availability: {len(territories)} territories")

    for d in all_pages(f"/v1/apps/{APP_ID}/inAppPurchasesV2?limit=200"):
        print("state:", d["attributes"]["productId"], d["attributes"]["state"])


if __name__ == "__main__":
    main()
