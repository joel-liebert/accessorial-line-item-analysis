#---- import packages ----
library(bigrquery)
library(DBI)
library(tidyverse)

#---- load data ----
bqcon <- dbConnect(
  bigrquery::bigquery(),
  project = "freightwaves-data-science"
)

query1 = 
  "with data as (
    select
      ship_date
      ,date_trunc(ship_date, month) as month
      ,cass_shipment_id
      ,concat(substring(origin_postal_code, 1, 3), '-', substring(destination_postal_code, 1, 3)) as zip3_lane
      ,case
        when substring(origin_postal_code, 1, 1) in ('0', '1', '2') then 'Atlantic'
        when substring(origin_postal_code, 1, 1) in ('3', '7') then 'South'
        when substring(origin_postal_code, 1, 1) in ('4', '5', '6') then 'Midwest'
        when substring(origin_postal_code, 1, 1) in ('8', '9') then 'West'
        else 'N/A'
        end as orig_region
      ,case
        when substring(destination_postal_code, 1, 1) in ('0', '1', '2') then 'Atlantic'
        when substring(destination_postal_code, 1, 1) in ('3', '7') then 'South'
        when substring(destination_postal_code, 1, 1) in ('4', '5', '6') then 'Midwest'
        when substring(destination_postal_code, 1, 1) in ('8', '9') then 'West'
        else 'N/A'
        end as dest_region
      ,distance
      ,case
        when distance < 100 then 'City (0-100)'
        when distance < 250 then 'Short (100-250)'
        when distance < 500 then 'Mid (250-500)'
        when distance < 750 then 'Tweener (500-750)'
        when distance < 1000 then 'Long (750-1000)'
        else 'Extra-long (1000+)'
        end as LOH
      ,carrier_name
      ,case
        when upper(accessorial_charge_description) like '%FUEL%SUR%' then 'FUEL SURCHARGE'
        when upper(accessorial_charge_description) like '%SUR%FUEL%' then 'FUEL SURCHARGE'
        when upper(accessorial_charge_description) like '%FUEL%CH%' then 'FUEL CHARGE'
        else 'OTHER'
        end as accessorial_charge_description
      ,accessorial_charge_amount
      ,amount_paid
      ,count(distinct accessorial_charge_description) over (partition by cass_shipment_id) as charge_count
  
    from `freightwaves-data-factory.warehouse.beetlejuice`
    
    where (upper(accessorial_charge_description) like '%FUEL%SUR%'
        or upper(accessorial_charge_description) like '%SUR%FUEL%'
        or upper(accessorial_charge_description) like '%FUEL%CH%')
      and origin_country_code in ('US', 'USA') and destination_country_code in ('US', 'USA')
      and origin_state != 'CA' and destination_state != 'CA'
      and transportation_mode_description = 'TRUCKLOAD (DRY VAN)'
      and ship_date >= '2022-01-01' and ship_date < current_date
      and distance is not null and distance > 25 and distance < 3300
      and amount_paid > 100
  ),
  load_data as (
    select
      cass_shipment_id
      ,ship_date
      ,month
      ,orig_region
      ,dest_region
      ,zip3_lane
      ,carrier_name
      ,distance
      ,LOH
      ,if (charge_count=1, accessorial_charge_description, 'BOTH') as charge_type
      ,sum(accessorial_charge_amount) as total_fuel
      ,amount_paid
    from data
    group by cass_shipment_id, ship_date, month, orig_region, dest_region, zip3_lane, carrier_name, distance, LOH, amount_paid, charge_count, accessorial_charge_description
  )
  select * from load_data
  order by carrier_name, distance, cass_shipment_id"

bj <- dbGetQuery(bqcon, query1)

#---- get surchage multipliers ----
# set up matrix
mpg = c(5, 6.5, 8)
fuel_charge_per_gallon = c(low=2, mid=2.5, high=3)
fuel_costs_per_gallon = c(3.6, 4.95, 5.8)
# miles = c(100, 500, 1000, 2000)

df1 <- tibble(mpg, fuel_charge_per_gallon, fuel_costs_per_gallon)

combos <- df1 %>% 
  expand(mpg, fuel_costs_per_gallon, fuel_charge_per_gallon) %>%
  mutate(fuel_charge_per_miles    = fuel_charge_per_gallon/mpg,
         fuel_surcharge_per_miles = (fuel_costs_per_gallon - fuel_charge_per_gallon)/mpg)

charge_vector    <- c(low=min(combos$fuel_charge_per_miles),
                      mid=mean(combos$fuel_charge_per_miles),
                      high=max(combos$fuel_charge_per_miles))

surcharge_vector <- c(low=min(combos$fuel_surcharge_per_miles),
                      mid=mean(combos$fuel_surcharge_per_miles),
                      high=max(combos$fuel_surcharge_per_miles))

#---- example ----
x = miles[1]
# to calculate fuel charge
combos$fuel_costs_per_gallon * (x/mpg)
# to calculate fuel surcharge
combos$fuel_surcharge_per_miles * x

#---- sample data ----
sample <- bj$cass_shipment_id %>% sample(nrow(bj))
sampled_data <- bj %>% filter(cass_shipment_id %in% sample)

#---- estimate fuel costs ----
estimated_data <- sampled_data %>%
  filter(charge_type != 'BOTH',
         orig_region != 'N/A',
         dest_region != 'N/A') %>% 
  # mutate(cd_total_fuel = cume_dist(total_fuel),
  #        cd_amount_paid = cume_dist(amount_paid)) %>%
  # # remove outliers
  # filter(cd_total_fuel >= 0.1 & cd_total_fuel <= 0.9 &
  #          cd_amount_paid >= 0.1 & cd_amount_paid <= 0.9) %>% 
  mutate(low_fuel_proj  = charge_vector['low']*distance  + surcharge_vector['low']*distance,
         mid_fuel_proj  = charge_vector['mid']*distance  + surcharge_vector['mid']*distance,
         high_fuel_proj = charge_vector['high']*distance + surcharge_vector['high']*distance,
         rpm           = total_fuel/distance,
         low_rpm_proj  = low_fuel_proj/distance,
         mid_rpm_proj  = mid_fuel_proj/distance,
         high_rpm_proj = high_fuel_proj/distance)

#---- aggregate at charge type level ----
summary_data <- estimated_data %>% 
  mutate(LOH = factor(LOH, levels=c('City (0-100)', 'Short (100-250)', 'Mid (250-500)', 'Tweener (500-750)', 'Long (750-1000)', 'Extra-long (1000+)'))) %>% 
  group_by(LOH, charge_type) %>% 
  summarize(count = n(),
            mean_total_fuel = mean(total_fuel),
            mean_amount_paid = mean(amount_paid),
            mean_low_proj = mean(low_fuel_proj),
            mean_mid_proj = mean(mid_fuel_proj),
            mean_high_proj = mean(high_fuel_proj),
            mean_rpm = mean(rpm),
            low_rpm_proj = mean(low_rpm_proj),
            mid_rpm_proj = mean(mid_rpm_proj),
            high_prm_proj = mean(high_rpm_proj))

summary_fuel_plot <- summary_data %>% 
  ggplot(aes(charge_type, mean_total_fuel)) +
  geom_bar(stat='identity') +
  facet_wrap(LOH~., scales='free') +
  geom_errorbar(data=summary_data, aes(x=charge_type, ymin=mean_low_proj, ymax=mean_high_proj), color='red') +
  theme_classic() +
  labs(x='Charge Type', y='Mean Total Fuel Costs', title='Total Fuel Costs vs Estimated Total Fuel Costs')
summary_fuel_plot
summary_rpm_plot <- summary_data %>% 
  ggplot(aes(charge_type, mean_rpm)) +
  geom_bar(stat='identity') +
  facet_wrap(LOH~., scales='free') +
  geom_errorbar(data=summary_data, aes(x=charge_type, ymin=low_rpm_proj, ymax=high_prm_proj), color='red') +
  theme_classic() +
  labs(x='Charge Type', y='Mean RPM', title='RPM vs Estimated RPM')
summary_rpm_plot

lane_summary_data <- estimated_data %>% 
  mutate(LOH = factor(LOH, levels=c('City (0-100)', 'Short (100-250)', 'Mid (250-500)', 'Tweener (500-750)', 'Long (750-1000)', 'Extra-long (1000+)'))) %>% 
  group_by(LOH, orig_region, dest_region, zip3_lane, charge_type) %>% 
  summarize(count = n(),
            mean_total_fuel = mean(total_fuel),
            mean_amount_paid = mean(amount_paid),
            mean_low_proj = mean(low_fuel_proj),
            mean_mid_proj = mean(mid_fuel_proj),
            mean_high_proj = mean(high_fuel_proj),
            mean_rpm = mean(rpm),
            low_rpm_proj = mean(low_rpm_proj),
            mid_rpm_proj = mean(mid_rpm_proj),
            high_rpm_proj = mean(high_rpm_proj))

LOH_summary_data <- lane_summary_data %>% 
  group_by(LOH, charge_type) %>% 
  summarize(count = n(),
            med_total_fuel = median(mean_total_fuel),
            med_amount_paid = median(mean_amount_paid),
            med_low_proj = median(mean_low_proj),
            med_mid_proj = median(mean_mid_proj),
            med_high_proj = median(mean_high_proj),
            med_rpm = median(mean_rpm),
            low_rpm_proj = median(low_rpm_proj),
            mid_rpm_proj = median(mid_rpm_proj),
            high_rpm_proj = median(high_rpm_proj))

LOH_summary_fuel_plot <- LOH_summary_data %>% 
  ggplot(aes(charge_type, med_total_fuel)) +
  geom_bar(stat='identity') +
  facet_wrap(LOH~., scales='free') +
  geom_errorbar(data=LOH_summary_data, aes(x=charge_type, ymin=med_low_proj, ymax=med_high_proj), color='red') +
  theme_classic() +
  labs(x='Charge Type', y='Median Total Fuel Costs', title='Total Fuel Costs vs Estimated Total Fuel Costs')
LOH_summary_fuel_plot
LOH_summary_rpm_plot <- LOH_summary_data %>% 
  ggplot(aes(charge_type, med_rpm)) +
  geom_bar(stat='identity') +
  facet_wrap(LOH~., scales='free') +
  geom_errorbar(data=LOH_summary_data, aes(x=charge_type, ymin=low_rpm_proj, ymax=high_rpm_proj), color='red') +
  theme_classic() +
  labs(x='Charge Type', y='Median RPM', title='RPM vs Estimated RPM')
LOH_summary_rpm_plot
LOH_violin_fuel_plot <- lane_summary_data %>% 
  ggplot(aes(charge_type, mean_total_fuel, fill=charge_type)) +
  geom_violin() +
  facet_wrap(LOH~., scales='free') +
  geom_errorbar(data=LOH_summary_data, aes(x=charge_type, ymin=med_low_proj, ymax=med_high_proj), color='red') + #in order for this to work, rename LOH$med_total_fuel to LOH$mean_total_fuel. idk why
  theme_classic()
LOH_violin_fuel_plot

