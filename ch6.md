# 6. 设计 Twitter

> **难度等级：中等**

让我们设计一个类 Twitter 网络服务。该服务的用户可以发布推文，关注其他人，以及将推文标注为喜欢。

## 1. 什么是 Twitter？

Twitter 是一个在线社交网络服务，用户可以发布和阅读不超过 140 个字的短消息，这样的消息称为「推文」。注册的用户可以发布和阅读推文，但是未注册的用户只能阅读推文。用户通过网页、短信息服务（SMS）或手机应用访问 Twitter。

## 2. 系统的要求和目标

我们将设计一个 Twitter 的简化版本，具备以下要求。

### 功能性要求

1. 用户可以发布新推文。

2. 用户可以关注其他用户。

3. 用户可以将推文标注为喜欢。

4. 服务应该可以创建和显示一个用户的时间线，包含该用户关注的所有用户发布的最新推文。

5. 推文可以包含图像和视频。

### 非功能性要求

1. 系统高度可用。

2. 生成时间线方面，系统可接受的延迟是 200 毫秒。

3. 一致性可能是一个问题（在可用性方面）；如果用户暂时没有看到推文，也是正常的。

### 扩展性要求

1. 搜索推文。

2. 回复推文。

3. 话题的趋势分析——当前的热门话题和搜索。

4. 给其他用户添加标签。

5. 推文通知。

6. 关注谁？如何推荐？

7. 瞬间。

## 3. 容量估算和限制条件

我们假设一共有 10 亿（1B）用户，其中有 2 亿（200M）日活跃用户（DAU）。同时假设每天有 1 亿条新推文，平均每个用户关注 200 个用户。

**每天有多少标注为喜欢的操作**？如果平均每个用户每天将 5 条推文标注为喜欢，则有：

200M users * 5 favorites => 1B favorites

**我们的系统每天生成多少推文阅读**？我们假设平均每个用户每天访问时间线两次并且访问其他 5 个用户的页面。如果每个页面上用户看到 20 条推文，则我们的系统每天生成 280 亿个推文阅读：

200M DAU * ((2 + 5) * 20 tweets) => 28B/day

**存储估算**：考虑每条推文有 140 个字，在不压缩的情况下每个字需要 2 个字节存储。我们假设每条推文需要 30 字节存储元数据（例如推文 ID、时间戳、用户 ID 等）。我们需要的总存储量是：

100M * (280 + 30) bytes => 30GB/day

如果使用 5 年，需要多少存储量？用户的数据、关注、喜欢需要多少存储量？这个问题作为练习。

不是所有的推文都有多媒体。我们假设平均每 5 条推文有图像，每 10 条推文有视频。另外假设平均每张图像的大小是 200KB，每个视频的大小是 2MB。这样每天将会新产生 24TB 的多媒体。

(100M/5 photos * 200KB) + (100M/10 videos * 2MB) ~= 24TB/day

**带宽估算**：由于每天的总传入是 24TB，这对应 290MB/秒。

我们每天有 280 亿个推文阅读。我们必须显示每条推文的图像（如果有图像），但是我们假设用户在时间线中每 3 个视频才观看 1 个视频。因此，总传出是：

(28B * 280 bytes) / 86400s of text => 93MB/s
+ (28B/5 * 200KB ) / 86400s of photos => 13GB/S
+ (28B/10/3 * 2MB ) / 86400s of Videos => 22GB/s
Total ~= 35GB/s

## 4. 系统 API

> **提示：当我们确定需求之后，定义系统 API 总是好的做法，可以显性说明系统应该是什么样的。**

我们可以使用 SOAP 或 REST API 将我们的服务的函数公开。以下为发布新推文的 API 的定义：

```
tweet(api_dev_key, tweet_data, tweet_location, user_location, media_ids, maximum_results_to_return)
```

**参数**：
api_dev_key（string）：一个已注册的帐号的 API 开发者关键字。关键字将和其他字段一起根据用户分配的额度限制用户。
tweet_data（string）：推文的文本，通常不超过 140 个字。
tweet_location（string）：（可选）推文的地点（经度和纬度）。
user_location（string）：（可选）发布推文的用户的地点（经度和纬度）。
media_ids（number[]）：（可选）与推文关联的多媒体编号列表（所有的需要独立上传的多媒体图像、视频等）。

**返回**：（string）
如果推文发布成功，将返回访问该推文的 URL。否则，返回一个合适的 HTTP 错误。

## 5. 高阶设计

我们需要一个高效存储所有新推文的系统，存储速度是 100M/86400s => 1150 条推文/秒，阅读速度是 28B/86400s => 325K 条推文/秒。根据需求可知，这是一个重读（read-heavy）的系统。

在高阶层次上，我们需要多个应用服务器处理所有的请求，负载均衡器在前面将流量分流。在后端，我们需要一个高效的数据库，要求可以存储所有的新推文并且可以支持很大的阅读量。我们也需要一些文件存储用于存放图像和视频。

![](/img/ch6_1.png)

虽我们预期每天的写负载是 1 亿条推文，读负载是 280 亿条推文。这表示我们的系统平均每秒接收 1160 条新推文和 32.5 万个读请求。然而，流量在一天中的分布是不平均的，在高峰时间我们应该预期每秒至少有几千个写请求和大约 100 万个读请求。当设计系统架构时应该记住这一点。

## 6. 数据库模型

我们需要存储的数据包括用户、推文、喜欢的推文和被关注者。

Tweet 表

<table>
	<tr>
		<th colspan="2">Tweet</th>
	</tr>
	<tr>
		<td>PK</td>
		<td>TweetID: int</td>
	</tr>
	<tr>
		<td></td>
		<td>
			<div>UserID: int</div>
			<div>Content: varchar(140)</div>
			<div>TweetLatitude: int</div>
			<div>TweetLongitude: int</div>
			<div>UserLatitude: int</div>
			<div>UserLongitude: int</div>
			<div>CreationDate: datetime</div>
			<div>NumFavorites: int</div>
		</td>
	</tr>
</table>

User 表

<table>
	<tr>
		<th colspan="2">User</th>
	</tr>
	<tr>
		<td>PK</td>
		<td>UserID: int</td>
	</tr>
	<tr>
		<td></td>
		<td>
			<div>Name: varchar(20)</div>
			<div>Email: varchar(32)</div>
			<div>DateOfBirth: varchar(32)</div>
			<div>CreationDate: datetime</div>
			<div>LastLogin: datatime</div>
		</td>
	</tr>
</table>

UserFollow 表

<table>
	<tr>
		<th colspan="2">UserFollow</th>
	</tr>
	<tr>
		<td>PK</td>
		<td>
			<div>UserID1: int</div>
			<div>UserID2: int</div>
		</td>
	</tr>
</table>

Favorite 表

<table>
	<tr>
		<th colspan="2">Favorite</th>
	</tr>
	<tr>
		<td>PK</td>
		<td>
			<div>TweetID: int</div>
			<div>UserID: int</div>
		</td>
	</tr>
	<tr>
		<td></td>
		<td>
			<div>CreationDate: datetime</div>
		</td>
	</tr>
</table>

在选择 SQL 和 NoSQL 数据库存储上述模型方面，请参考「设计 Instagram」的「数据库模型」部分。

## 7. 数据分片

由于我们每天的新推文数量巨大，读负载也极高，我们需要将数据分布到多台机器上，使得我们的读写操作可以高效。我们有很多选项可以将数据分片，以下分别列举：

**基于用户 ID 分片**：我们可以尝试将一个用户的所有数据存储在一台服务器上。存储时，我们可以将用户 ID 传给我们的哈希函数，哈希函数将用户映射到一台数据库服务器，数据库服务器上存储所有用户发布的推文、喜欢的推文、关注者等信息。当查询一个用户发布的推文/关注者/喜欢的推文时，我们可以使用寻找用户数据的哈希函数从数据库服务器中读取相应的信息。这个方法存在一些问题：

1. 如果用户成为热门用户会如何？这样服务器上将会有大量关于该用户的查询。高负载将影响我们服务的性能。

2. 经过一段时间之后，一些用户和其他用户相比，可能发布大量推文或者关注大量用户。维护增长用户数据的均匀分配是非常困难的。

为了从这些情形中恢复，我们或者需要重新将数据分片，或者需要使用一致性哈希。

**基于推文 ID 分片**：我们的哈希函数将每个推文 ID 映射到随机的一台存储该推文的服务器。为了搜索推文，我们必须查询所有的服务器，每个服务器将返回一个推文集合。一个中心化服务器将聚集这些结果并返回给用户。我们用时间线的生成举例，以下是我们的系统生成用户时间线需要执行的操作：

1. 我们的应用服务器将找到用户关注的所有用户。

2. 应用服务器将查询发送到所有的数据库服务器，找到这些用户发布的推文。

3. 每个数据库服务器将找到每个用户的推文，将推文按照发布时间由近及远排序并返回最靠前的推文。

4. 应用服务器将所有的结果合并然后再次排序，将最靠前的结果返回给用户。

这个方法解决了热门用户的问题，但是不同于基于用户 ID 分片，我们必须查询所有的数据库分片才能找到一个用户的推文，这会导致延迟时间更高。

**基于推文创建时间分片**：基于创建时间存储推文的好处是可以快速获取所有的最靠前推文，而且我们只需要查询很小一部分服务器。问题是流量负载不会被分布到多台服务器，例如当写操作时，所有的新推文都进入一台服务器，其余服务器都是闲置的。类似地，当读操作时，存储最近数据的服务器和存储老数据的服务器相比，将有非常高的负载。

**我们是否可以结合基于推文 ID 和推文创建时间分片**？如果我们不单独存储推文创建时间，而是用推文 ID 反映创建时间，则可以结合两者的优势。使用这种方法可以很快找到最近发布的推文。为了实现这一点，我们必须在系统中将每个推文 ID 设为全局唯一，且每个推文 ID 也必须包含时间戳。

我们可以使用新纪元时间实现这一点。推文 ID 由两部分组成，第一部分是新纪元时间的秒数，第二部分是自动增加序列。因此，生成新的推文 ID 时，可以获取当前的新纪元时间然后将一个自动增加的数字添加在后面。我们可以从推文 ID 计算得到分片数字，并将推文存储在相应的分片中。

推文 ID 的大小时多少？假设新纪元时间从今天开始，存储将来 50 年的描述需要多少比特？

86400 sec/day * 365 (days a year) * 50 (years) => 1.6B

![](/img/ch6_2.png)

我们需要 31 个比特存储这个数字。由于平均每秒有 1150 条新推文，我们可以分配 17 个比特存储自动增加序列。推文 ID 的长度是 48 比特。因此每秒我们可以存储 2^17 => 13 万条新推文。我们可以在每秒将自动增加序列归零。考虑到容错和更好的性能，我们可以有两台数据库服务器生成自动增加关键字，一台服务器生成偶数关键字，另一台服务器生成计数关键字。

假设我们当前的新纪元时间秒数是 1483228800，推文 ID 如下所示：

1483228800 000001
1483228800 000002
1483228800 000003
1483228800 000004
……

如果我们将推文 ID 设为 64 比特（8 字节）长，我们可以存储将来 100 年的推文，也可以使用毫秒级的粒度存储。

上述方法中，生成时间线时我们仍然必须查询所有的服务器，但是读和写操作的速度会显著提升。

1. 由于我们没有任何二级索引（查询时间），因此可以减少写操作的延迟。

2. 读操作时，我们不需要基于创建时间过滤，因为主键包含了新纪元时间。

## 8. 缓存

我们可以为数据库服务器引入缓存，用于缓存热门推文和用户。我们可以使用现成的解决方案，例如 Memcache，存储整个推文对象。在访问数据库之前，应用服务器可以快速检查缓存中是否又目标推文。基于客户端的使用模式，我们可以决定需要多少缓存服务器。

**哪种缓存替换机制最适合我们的需求**？当缓存已满，我们需要将一条推文替换成更新/更热门的推文，我们应该如何选择？最近最少使用（LRU）可以是我们系统的一个合适的机制。该机制下，我们首先丢弃最近最少访问的推文。

**我们如何得到更智能的缓存**？如果我们遵循 80-20 法则，20% 的推文产生 80% 的读流量，即特定推文非常热门，大多数用户都会阅读。这点说明我们应该尝试缓存每个分片中的每天被阅读的推文的 20%。

**缓存最近数据如何**？这种方法有助于我们的服务。假设 80% 的用户只查看过去 3 天的用户，我们可以尝试缓存过去 3 天的全部推文。假设我们用缓存服务器缓存过去 3 天所有用户发布的推文。根据上述估算，我们每天又 1 亿条新推文或者 30GB 新数据（不包含图像和视频）。如果我们想存储过去 3 天的所有推文，我们需要的内存小于 100GB。这些数据可以存入一台服务器，但是我们应该将其复制到多台服务器上，以降低读流量，减少缓存服务器的负载。所以在任何时候当我们生成用户的时间线时，我们可以询问缓存服务器是否有该用户的所有最近推文。如果有，我们只要返回缓存中的全部数据即可。如果缓存中没有足够的推文，我们必须查询后端服务器获得数据。使用类似的设计，我们可以尝试缓存过去 3 天的图像和视频。

我们的缓存如同哈希表，关键字是用户 ID，值是双向链表，双向链表包含该用户过去 3 天的所有推文。由于我们想首先获得最近的数据，我们总是可以将新推文插入链表的头部，意味着所有的老推文都在链表的尾部附近。因此，我们可以从链表的尾部删除推文，为新推文留出空间。

![](/img/ch6_3.png)

## 9. 时间线生成

关于时间线生成的具体讨论，参考「设计 Facebook 的新闻推送」。

## 10. 备份和容错

由于我们的系统是重读的，我们可以为每个数据库分片设定多个二级数据库服务器。二级服务器只用于读流量。所有的写操作首先进入主服务器然后被复制到二级服务器。该模型也支持容错，任何时候当主服务器宕机了，可以使用二级服务器实现失效转移。

## 11. 负载均衡

我们可以在系统中的 3 个位置增加负载均衡层：1. 在客户端和应用服务器之间；2. 在应用服务器和数据库备份服务器之间；3. 在聚集服务器和缓存服务器之间。初始时，可以使用一个简单的轮询调度（Round Robin）方法，将进入的请求平均地分布到各台服务器。这样的负载均衡实现简单，不会引入新的开销。该方法的另一个好处是如果一台服务器宕机了，负载均衡可以将其移出轮询，停止向其发送任何流量。轮询调度负载均衡的一个问题是没有考虑服务器的负载。如果一台服务器负载过重或者速度过慢，负载均衡并不会停止向这台服务器发送新请求。为了处理这个问题，可以使用一个更智能的负载均衡解决方案，该方案周期性地查询后端服务器获取负载信息，并基于该信息调整流量。

## 12. 监控

对于我们的系统的监控能力是至关重要的。我们应该持续手机数据以实时了解系统的运行情况。我们可以收集以下数值，了解我们服务的性能：

1. 每天/每秒的新推文数量，每天的峰值是多少？

2. 时间线发布状态，我们的系统每天/每秒发布多少条推文。

3. 用户可见的刷新时间线的平均延迟。

通过监视这些数值，我们可以发现是否需要更多的备份、负载均衡或缓存。

## 13. 扩展性要求

**我们如何处理信息流**？获取一个用户关注的用户的所有最新推文，然后按照时间合并/排序。使用页码获取/显示推文。只获取一个用户关注的所有用户的最靠前的 N 条推文。这里的 N 将取决于客户端的视口（Viewport），因为在手机上显示的推文数少于在网页上显示的推文数。我们也可以缓存后一部分靠前的推文以提升速度。

另一种做法是，我们可以实现生成信息流以提升效率。细节方面请参考「设计 Instagram」的「排名和时间线生成」部分。

**回复**：由于数据库中已有每条推文对象，我们可以在回复对象中存储原始推文的 ID 且不存储任何内容。

**热门话题**：我们可以缓存过去 N 秒内出现频率最多的话题标签或者查询语句，并持续每隔 M 秒更新一次。我们可以基于推文、查询语句、回复或喜欢的频率对热门话题排序。我们可以对展示给更多用户的话题赋予更多的权重。

**关注谁**？**如何推荐**？这个特征将改善用户关系。我们可以推荐某个用户关注的用户的朋友。我们可以深入 2 到 3 层寻找著名的用户作为推荐。我们可以给拥有更多粉丝的用户更多的倾向性。

由于任何时候只能有少数推荐，使用机器学习（ML）重新排列和调整优先级。机器学习标志可以包含最近粉丝数量增加的用户、关注当前用户的其他用户的共同关注、共同的地点或兴趣等。

**瞬间**：从不同网站获取过去 1 到 2 小时的热点新闻，找到相关推文，将这些推文优先级提升，使用机器学习——有监督学习或聚类的方式将这些推文分类（新闻、自主、金融、娱乐等）。然后我们可以将这些文章以热门话题的形式展示在瞬间中。

**搜索**：搜索包含索引、排序和获取推文。下一个问题「设计 Twitter 搜索」中讨论一个类似的方案。
