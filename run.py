from app import create_app, db
from sqlalchemy import text

app = create_app()

# --- AUTO DATABASE FIX ---
# This block runs right before the app starts to manually apply the missing database updates.
with app.app_context():
    # 1. This will safely create the new 'monthly_air_rates' table
    db.create_all()
    
    # 2. This safely injects the missing 'transport_mode' column into your existing table
    try:
        db.session.execute(text("ALTER TABLE shipment_batches ADD COLUMN transport_mode VARCHAR(20) DEFAULT 'Sea' NOT NULL;"))
        db.session.commit()
        print("Successfully added transport_mode column to shipment_batches.")
    except Exception as e:
        db.session.rollback()
        # If the column already exists (e.g. on subsequent reboots), this safely ignores the error
        pass
# -------------------------

if __name__ == "__main__":
    app.run(debug=True)
