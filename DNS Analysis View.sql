
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
where (to_timestamp(dl.timestamp) at time zone 'America/Chicago') between '2026-03-01' and '2026-04-27'
	and nd.device_type = 'IoT'
;

select distinct friendly_name
from iot_data
;

--drop view iot_data;

select count(*)
from iot_data;

select distinct friendly_name
from iot_data
;

select distinct client,
	friendly_name,
	min(date_time) as first_query,
	max(date_time) as last_query
from iot_data
group by client,
	friendly_name
order by last_query
;


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

/* data for bar chart with max/median daily query count, looking for anomolies
 * again removed smart plug as it has almost 7x the activity of any other device
 */

with cte as (
	select friendly_name,
		date_time::date as date,
		count(id) as num_queries
	from iot_data
where friendly_name != 'Smart Plug'
	group by friendly_name,
		date_time::date
),
cte2 as (
select cte.friendly_name as device,
	 max(cte.num_queries) over (partition by cte.friendly_name) as max_queries
from cte
group by cte.friendly_name,
	cte.num_queries
)
select cte2.device,
	percentile_cont(0.5) WITHIN GROUP (ORDER BY cte.num_queries) AS median_daily_queries,
	cte2.max_queries as max_daily_queries
from cte2
join cte on cte.friendly_name = cte2.device
group by cte2.device
	,cte2.max_queries
order by median_daily_queries desc
;

-- biggest outlier is the 3d-printer having a median of 38 and a max day of 2442. looking for details
select date_time::date as date,
	extract(hour from date_time) as hour,
	count(id) as num_queries
from iot_data
where --extract(dow from date_time) = 1
	--extract(hour from date_time) between 16 and 20
	friendly_name = '3D-Printer'
group by date,
	hour
having count(id) > 76 -- checking any days that are double or more the daily median value
order by date,
	hour
;


-- where are the 3d printer queries going
select domain,
	count(id) as num_queries
from iot_data
where friendly_name = '3D-Printer'
group by domain
order by count(id) desc
;

-- april 6th, 3d printer queries
select domain,
	count (id)
from iot_data
where date_time::date = '2026-04-06' and
	extract(hour from date_time) between 16 and 19 and
	friendly_name = '3D-Printer'
group by domain
order by count(id) desc
;



/* This 3D printer talks to multiple Chinese cloud vendors with servers located in the US
 * China and Japan regularly without any user interaction:
 * Alibaba Cloud			File/object storage
 * Flashforge sz3dp.com		Device control, cloud print, firmware updates
 * Qiniu Cloud				Video/camera streaming
 * NetEase Yunxin			Real-time messaging and presence, analytics
 * 
 * None of this is disclosed in plain language anywhere in the product packaging or setup process.
 *  It's buried in a terms of service that most consumers never read. DNS logs made it visible
 *  in a way nothing else on the network would have.
 */

-- April 22 to 25th mini spike
select date_time::date as date,
	domain,
	count(id) as num_queries
from iot_data
where friendly_name = '3D-Printer'
	and date_time::date in ('2026-04-22','2026-04-23', '2026-04-25')
group by date,
	domain
order by date,
	count(id) desc
;

/* The flashforge printer maintains persistent background communication with four cloud platforms operated
 * by Chinese technology companies.  This traffic occurs continuously without user internaction and was
 * undisclosed in the product documentation.  Queries follow a distrubuted pattern across all four vendors
 * Alibaba Cloud for file storage, Flashforge/sz3dp.com for device control and firmware updates, Qiniu for
 * video streaming infrastructure, and NetEase Yunxin for real-time messaging and analytics. This establishes
 * a clear behavioral baseline against which anomalous activity can be measured.
 */



select 
    min(date_time) as first_ping,
    max(date_time) as last_ping,
    count(*) as total_queries,
    extract(epoch from (max(date_time) - min(date_time)))/3600 as duration_hours
from iot_data
where date_time::date = '2026-04-06'
    and friendly_name = '3D-Printer'
    and domain = 'api.voxelshare.com'
;
/* 1863 of these queries to api.voxelshare.com happen between 4:08pm and 7:27pm,
 * 1942 of them between 1:39pm and 7:27pm on April 6th. There are only 13 other
 * queries to this domain in the entirety of the dataset, all on April 5th.
 */


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

select 
    date_time,
    extract(epoch from (date_time - lag(date_time) over (order by date_time))) as seconds_between
from iot_data
where date_time::date = '2026-04-06'
    and friendly_name = '3D-Printer'
    and domain = 'api.voxelshare.com'
order by date_time
;

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


/* Breakdown:
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
 */

/* DNS logs recorded 1,942 queries to api.voxelshare.com beginning on 4/6. The device owner was not home, had not
 * installed any new software, and was not interacting with the printer. No user-initiated explanation for this activity 
 * exists. This behavior was invisible to the homeowner until DNS log analysis was performed
 * 
 * What api.voxelshare.com Is:
 * VoxelShare / FlashCloud is Flashforge's integrated cloud platform that enables cloud-based management and control
 *  of 3D printers, cloud-based uploading and storage of print files, and social sharing functionality
 * 
 * further research found the following
 * Flashforge's terms explicitly state that by using their services, you "acknowledge and expressly consent that
 * Flashforge may collect, use, process, analyze, review, store, transmit, and disclose account, device, network,
 * and job-related data," including cross-border transfers
 * Cross-border transfers" is the polite legal term for "your data goes to China."
 */

-- I'm going to map all the locations this printer is talking to.
select domain,
	count(id) as num_queries
from iot_data
where friendly_name = '3D-Printer'
group by domain
order by num_queries desc
;


-- top 5 devices for chattiness
select friendly_name,
	count(id) as num_queries
from iot_data
group by friendly_name
order by count(id) desc
limit 5
;

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

-- I'm going back prior to my 8 week window to get more data on the smart plug.
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

select domain,
	count(id) as num_queries
from iot_data
where friendly_name = 'Smart Plug'
group by domain
order by count(id) desc

/* The smart plug was connected on 4/23 and since then has been sending a query approximately every
 * 5 seconds.  When it was last connected, it sent between 2 and 10 queries per day.  I'm trying to keep
 * all my findings and data as information I can find within the DNS records but i had to find the
 * explanation for this externally.  It's a Wemo smart plug and a quick web search found that Wemo is
 *  owned by Belkin and that Belkin has discontinued Wemo cloud services and app support for many
 *  devices as of January 31, 2026 this tells me that after the device was disconnected in February,
 *  the next time it was connected it went to find the no longer existing cloud service, and could not,
 *  so it's been trying to phone home every 5 seconds since resulting in approximately 17,232 queries per
 * day.  This device can still be controlled fine through the alexa app so without the DNS logs, the 
 * device would appear to be functioning normally.  Nothing from the device itself indicates a problem
 * i've blocked the domain it queries on my DNS server, It will continue to query every 5 seconds, but 
 * this will prevent the traffic reaching the internet as the site it's trying to query no longer exists
 * it is just a waste of bandwidth.
 */

select domain,
	count(id) as num_queries
from iot_data
where friendly_name = 'Smart Plug'
group by domain
order by num_queries desc
;


-- domains of top 5 devices and seperating out type of query.
select domain,
	count(id) num_queries,
	query_result,
	friendly_name,
	case when domain like any(array['%advertising%',
		'%adsystem%'])
		then 'Ads'
	when domain like any(array['%ntp%',
		'%time%'])
		then 'Time Update'
	when domain like any(array['%minerva%',
		'%crashlytics%',
		'%firebase%',
		'%metrics%']) 
		then 'Tracking/Telemetry'
	when domain like any(array['%diagnostic.networking%',
		'%amazonaws.com',
		'%captiveportal.com%',
		'%amazonvideo%',
		'%august.com%',
		'%digitaloceanspaces.com%',
		'%amazon%',
		'%pushd%',
		'%ecobee%',
		'meethue.com',
		'%alexa%',
		'%messaging%'])
		then 'Device Functionality'
	when domain like any(array['%update%',
		'%-ota.%'])
		then 'Software Updates'	
	else 'other'
	end as category
from iot_data
where friendly_name in 
	(select friendly_name
	from iot_data
	where friendly_name != 'Smart Plug'
	group by friendly_name
	order by count(id) desc
	limit 5)
group by domain,
	query_result,
	friendly_name
--num_queries desc
;

