# accessorial-line-item-analysis
Investigating accessorial line items to gain a better understanding of how base rate, fuel rate, and accessorial charges are recorded.

We currently use line items tagged as 'base rate' or 'base freight' as the linehaul rate we provide as our contract rate (after we do all our aggregation) and we also provide a fuel rate which is aggregated similarly from line items that look like 'fuel'.  There is a strong belief that people are not consistent in how they bill these things, so one person's base rate might be someone else's base rate + fuel or base rate + accessorial.Everyone is on board that base rate and fuel must be combined to give us a more standard 'all-in' rate but they are not convinced we must also include (actual) accessorials (I make the distinction because all of these categories are listed as accessorial categories in the data set).
The belief is that we don't want to be putting in accessorial charges that are unrelated to the standard nature of the load in our 'all-in' rate.  BUT if people don't always put accessorials in as some sort of accessorial line item then it's hard to differentiate between base rate and accessorial and the total sum (amount_paid field) of all line items should just be used.

Using this table:

freightwaves-data-factory.warehouse.beetlejuice

Using these fields (different combinations of them, all of them, one at a time):

origin/destination

transportation_mode_description

billed_weight

ship_weight

freight_class

distance

accessorial_charge_description

accessorial_charge_amount

carrier_name

primary_naics_code

system_type

ship_date

bill_date

deliver_date

shipper_master_code

We want to understand:

What are all the possible accessorial_charge_description levels?

How many loads DO NOT have accessorial charges? (tricky because ‘base charge’ and ‘fuel’ charges are also listed in accessorial_charge_description.

Percentage of the whole and/or group

What carriers/shippers accessorial trends/patterns do we see?

Anything interesting about this data (very broad I know)

 

Ultimately this field:

amount_paid

Is the total of all line items (all accessorial_charge_description items) for any given cass_shipment_id.  We want to know how different this total is vs. a total that excludes accessorials (particularly accessorials that seem to be out of the ‘norm’ for the load - like detention, and {ASK A MARKET EXPERT ONCE YOU KNOW WHAT THE OPTIONS ARE}).  Accessorials like tolls and appointment fees can probably stay included in the total cost.

 

For reference:
Notes from 8/10/22 meeting with Go to Market:

Accessorial - dispersion of these - frequency by lane - category type etc.

How many are there? What are the categories? Frequency

By Lane

Unique shipper IDs (we know …. some )

% of shippers who have base, fuel, accessorial

Large shippers own some lanes

Detention should always be excluded

Tolls and appt fees can be lumped in
