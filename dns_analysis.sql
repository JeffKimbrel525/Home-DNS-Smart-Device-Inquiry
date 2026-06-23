
-- locking in exactly 8 weeks of data for final analysis
create or replace view iot_data as 
select dl.id,
	to_timestamp(dl.timestamp) at time zone 'America/Chicago' as date_time,
	dl.type,
	s.result as query_result,
	dl.domain,
	dl.client,
	nd.hwaddr,
	nd.name,
	nd.friendly_name,
	nd.device_type
from dns_logs dl
left join status s on s.status_id = dl.status
left join network_devices nd on nd.ip = dl.client
where (to_timestamp(dl.timestamp) at time zone 'America/Chicago') between '2026-03-01' and '2026-04-26'
	and nd.device_type = 'IoT'
;

select count(dl.id)
from dns_logs dl
join network_devices nd on nd.ip = dl.client 
where nd.device_type = 'IoT'
;

select *
from iot_data
;

-- What Devices do i have
select distinct friendly_name
from iot_data
;

-- how long has each device been present.
select distinct client,
	friendly_name,
	min(date_time) as first_query,
	max(date_time) as last_query
from iot_data
group by client,
	friendly_name
order by first_query
;


/* espressif.lan — Unidentified Device
 * An ESP32/ESP8266-based device with activity on 3/9 and 3/20 — two isolated days
 * eleven days apart. Despite checking all known household devices it remains unidentified,
 * though the sporadic pattern suggests an infrequently used consumer IoT device rather
 * than anything concerning.
 */

-- Pulling data for a Heatmap in Python
-- heatmap for all devices
-- came back and removed smart plug due to erroneous behavoir that i've explained later in this file
select count(*),
   extract(hour from date_time) as hour,
	extract(dow from date_time) as dow
from iot_data
where friendly_name != 'Smart Plug'
group by dow,
	hour
order by dow,
	hour
;


-- looking at sunday 10-12 am window
select date_time::date as date,
	--extract(hour from date_time) as hour,
	count(case when extract(hour from date_time) between 7 and 9 then id end) as pre_spike,
	count(case when extract(hour from date_time) between 10 and 12 then id end) as spike,
	count(case when extract(hour from date_time) between 13 and 15 then id end) as after_spike
from iot_data
where extract(dow from date_time) = 0 and
	friendly_name != 'Smart Plug' and
	extract(hour from date_time) between 7 and 15
group by date
--	hour
order by date	
;

-- looking at monday 7am spike from heatmap
select friendly_name as device,
	date_time::date as date,
	count(id) as num_queries
from iot_data
where extract(dow from date_time) = 1 and
	extract(hour from date_time) = 7
group by device,
	date
order by date
;

/* March 9th seems to have had a network wide event that caused many more
 * queries than average for all devices.  Likely internet outage?
 */

-- looking at monday evening spike
select friendly_name as device,
	date_time::date as date,
	extract(hour from date_time) as hour,
	count(id) as num_queries
from iot_data
where extract(dow from date_time) = 1 and
	extract(hour from date_time) between 16 and 19
group by device,
	date,
	hour
order by device,
	date	
;

-- confirmed that the monday evening 3 hourspike was the 3D-printer on april 6th
select friendly_name as device,
	date_time::date as date,
	extract(hour from date_time) as hour,
	count(id) as num_queries
from iot_data
where extract(dow from date_time) = 1 and
	extract(hour from date_time) between 16 and 19 and
	friendly_name = '3D-Printer'
group by device,
	date,
	hour
order by device,
	date	
;

-- what is the 3d printer talking to on april 6th
select domain,
	count(id) as num_queries
from iot_data
where friendly_name = '3D-Printer' and
	date_time::date = '2026-04-06'
group by domain
order by count(id) desc
;
/* This 3D printer regularly communicates with multiple Chinese cloud services, * 
 * None of this is disclosed in plain language anywhere in the product packaging or setup process.
 *  It's buried in a terms of service that most consumers never read. DNS logs made it visible
 *  in a way nothing else on the network would have.
 */

-- api.voxelshare.com only shows up on 2 separate days in the entire dataset
select 
    min(date_time) as first_ping,
    max(date_time) as last_ping,
    count(*) as total_queries,
    extract(epoch from (max(date_time) - min(date_time)))/3600 as duration_hours
from iot_data
where --date_time::date = '2026-04-06' and
    friendly_name = '3D-Printer' and
    domain = 'api.voxelshare.com'
;


-- looking more directly at timing of these queries
select 
    date_trunc('hour', date_time) as hour,
    count(*) as queries
from iot_data
where date_time::date = '2026-04-06'
    and friendly_name = '3D-Printer'
    and domain = 'api.voxelshare.com'
group by hour
order by hour
;


-- session analysis: identify distinct retry bursts by grouping queries 
-- with gaps of 5+ minutes, revealing the progression from backoff to aggressive retry loop
with gaps as (
    select
        date_time,
        extract(epoch from (date_time - lag(date_time) over (order by date_time))) as seconds_between
    from iot_data
    where date_time::date = '2026-04-06'
        and friendly_name = '3D-Printer'
        and domain = 'api.voxelshare.com'
),
sessions as (
    select
        date_time,
        seconds_between,
        sum(case when seconds_between >= 300 or seconds_between is null then 1 else 0 end)
            over (order by date_time) as session_num
    from gaps
)
select
    session_num,
    min(date_time)                  as session_start,
    max(date_time)                  as session_end,
    count(*)                        as query_count,
    round(max(seconds_between))     as session_gap,
    round(avg(seconds_between))     as avg_gap_sec
from sessions
group by session_num
order by session_num
;


/* 1942 queries to api.voxelshare.com happen between 1:39pm and 7:27pm on April 6th
 * 1863 of them happen between 4:08pm and 7:27pm. There are only 13 other
 * queries to this domain in the entirety of the dataset.  They all occurred on April 5th.
 * Breakdown:
 * 1:39–1:40pm — 19 rapid queries in about 40 seconds, then silence for 26 minutes.
 *  Possibly an initial handshake or authentication attempt.
 * 
 * 2:06–2:07pm — 4 quick queries, then silence for 105 minutes. It's trying again,
 *  but after no useful response, backed off with a long timeout.
 * 
 * 3:52–3:58pm — 56 queries in about 6 minutes, increasing frequency
 * the retry interval is tightening. Then a 10-minute gap.
 * 
 * 4:08pm onward — no more pauses, It gave up waiting for a clean response,
 *  and the device enters a full aggressive retry loop with no further backoff.
 *  From here it's relentless at roughly 8–11 seconds between queries all the way to 7:27pm
 * 
 * after 7:27 pm, no further queries to this domain in the rest of the dataset
 *
 * The device owner was not home, had not installed any new software, and was not interacting
 *  with the printer. No user-initiated explanation for this activity exists. This behavior
 *  was invisible to the homeowner until DNS log analysis was performed
 * 
 * What api.voxelshare.com Is:
 * VoxelShare / FlashCloud is Flashforge's integrated cloud platform that enables cloud-based management and control
 *  of 3D printers, cloud-based uploading and storage of print files, and social sharing functionality
 * 
 */



-- Smart Plug has only been connected since 4/23, how is this in top 5?
select 	date_time::date as day,
	extract(hour from date_time) as hour,
	count(id) as num_count
from iot_data
where friendly_name = 'Smart Plug'
group by day,
	hour
order by day,
	hour
;

-- extending smart plug search beyond the 8-week dataset to establish pre-disconnection baseline.
select (to_timestamp(dl.timestamp)at time zone 'America/Chicago')::date as date,
	extract(hour from to_timestamp(dl.timestamp)at time zone 'America/Chicago') as hour,
	extract(dow from to_timestamp(dl.timestamp) at time zone 'America/Chicago') as dow,
	count(dl.id) as query_count
from dns_logs dl
join network_devices nd on nd.ip = dl.client
join status s on s.status_id = dl.status
where nd.friendly_name = 'Smart Plug' --and to_timestamp(dl.timestamp) >= NOW() - INTERVAL '2 days'
group by date, hour, dow
order by date, hour
;

/* The smart plug was connected on 4/23 and since then has been sending a query approximately every
 * 5 seconds.  When it was last connected, it sent between 2 and 16 queries per day.  I'm trying to keep
 * all my findings and data as information I can find within the DNS records but I had to find the
 * explanation for this externally.  It's a Wemo smart plug and a quick web search found that Wemo is
 *  owned by Belkin and that Belkin has discontinued Wemo cloud services and app support for many
 *  devices as of January 31, 2026.  This tells me that after the device was disconnected in February,
 *  the next time it was connected it went to find the no longer existing cloud service, and could not,
 *  so it's been trying to phone home every 5 seconds since resulting in approximately 17,232 queries per
 * day.  This device can still be controlled through the alexa app so without the DNS logs, the 
 * device would appear to be functioning normally.  Nothing from the device itself indicates a problem.
 * I've blocked the domain it queries on my DNS server, It will continue to query every 5 seconds, but 
 * this will prevent the traffic reaching the internet as the site it's trying to query no longer exists.
 * It's just a waste of bandwidth.
 */

-- device statistics: median, mean, max, min, std dev, cv, days online, total queries
-- mean and final column ordering handled in Python
with daily_counts as (
	select friendly_name as device,
		date_time::date as date,
		count(id) as num_queries
	from iot_data
	group by friendly_name,
		date_time::date
),
device_aggregates as (
	select daily_counts.device,
		count(distinct daily_counts.date) as num_days,
		max(daily_counts.num_queries) as max_queries,
		min(daily_counts.num_queries) as min_queries,
		sum(daily_counts.num_queries) as total_queries,
		round(stddev(daily_counts.num_queries),2) as std_dev	 
	from daily_counts
	group by daily_counts.device
)
select device_aggregates.device,
	device_aggregates.num_days as days_online,
	percentile_cont(0.5) WITHIN GROUP (ORDER BY daily_counts.num_queries) AS median_daily_queries,
	device_aggregates.max_queries,
	device_aggregates.min_queries,
	device_aggregates.total_queries,
	device_aggregates.std_dev,
	round((device_aggregates.std_dev / (percentile_cont(0.5) WITHIN GROUP (ORDER BY daily_counts.num_queries)) * 100)::numeric,2) as cv
from device_aggregates
join daily_counts on daily_counts.device = device_aggregates.device
group by device_aggregates.device,
	device_aggregates.num_days, 
	device_aggregates.max_queries,
	device_aggregates.min_queries,
	device_aggregates.total_queries,
	device_aggregates.std_dev
order by total_queries desc
;

-- investigating devices with unusually high coefficient of variation (CV)
-- from the statistics table

-- garage door opener
select date_time::date as day,
	extract(hour from date_time) as hour,
	count(id) as num_queries
from iot_data
where friendly_name = 'Garage Door Opener'
group by day,
	hour
having count(id) > 10
order by day,
	hour
;
-- caused 100% by the March 9th spike already documented.

-- Blink Camera
select date_time::date as day,
	extract(hour from date_time) as hour,
	count(id) as num_queries
from iot_data
where friendly_name = 'Blink Camera'
group by day,
	hour
having count(id) > 10
order by day,
	hour
;
-- same result, spike on March 9th. 100% accounts for this.

-- Oven
select date_time::date as day,
	extract(hour from date_time) as hour,
	count(id) as num_queries
from iot_data
where friendly_name = 'Oven'
group by day,
	hour
having count(id) > 10
order by day,
	hour
;
-- same result, March 9th spike accounts for this entirely.


-- pulling hourly data for all devices to take to python for z-score analysis
select friendly_name as device,
	date_trunc('hour', date_time) as day_hour,
	count(id) as num_queries
from iot_data
group by device,
	day_hour
order by device,
	day_hour
;

-- full network query map for a closing map visual.
select distinct friendly_name as device,
	domain
from iot_data
;
