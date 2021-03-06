>





## 7.数据大小估算

估计有多少数据将进入每个表以及需要多少总存储空间，考虑10年的容量。

用户：假设每个“int”和“dateTime”是四个字节，用户表中的每一行将是68





## 10.数据分片

一起来讨论元数据分片的不同方案：

### a.基于`UserID`的分区

如果按UserID分区的话，用户的所有图片可以分配到同一个分区下。如果一个 DB分片是1TB，需要四个分片来存储3.7TB数据。为了更好的性能和可扩展性，保留10个分片。

通过 UserID%10 找到分片号进行数据存储。唯一标识图片的话，可以为每个PhotoID追加分片号。

**如何生成 PhotoID？**

对于PhotoID，每个 DB 分片有自己的自增序列，每个PhotoID中附加 ShardID，能做到数据唯一。

**这种分区方案有哪些问题？**

- 1.如何处理热门用户？一部分人关注这样的热门用户和很多其他人查看他们上传的照片。
- 2.有些用户的照片会比其他用户多，从而造成不均匀存储分布。
- 3.如果不能将用户的所有图片存储在一个分片上怎么办？如果分发用户的照片到多个分片上会导致更高的延迟吗？
- 4.将用户的所有照片存储在一个分片上可能会导致所有用户的照片不可用等问题，当出现该分片宕掉或因为高负载而带来高延迟。

### b.基于PhotoID分片

如果预先生成了唯一的 PhotoID，然后通过PhotoID % 10找到一个分片号，上面说的这些问题便会迎刃而解。不需要将 ShardID 与 PhotoID 追加在一起，因为PhotoID 本身在整个系统中都是唯一的。

**如何生成 PhotoID？** 

在这种分片方案下，不能在每个分片中都有一个自动递增的序列来生成PhotoID，因为首先需要知道 PhotoID 才能找到存储它的分片号。 一种解决方案是使用单独的专门数据库来生成自动递增的ID。 如果我们的 PhotoID 可以适配 64 位，可以定义一个只包含 64 位 ID 字段的表。 所以每当在系统中添加一张照片，在这个表中插入一个新行并将该 ID ，这个ID便是新插入的图片的PhotoID 。

**这个自增ID的数据库会单点故障吗？**

答案是肯定的， 一种解决方法可以定义两个这样的数据库，一个生成偶数 ID，另一个生成奇数ID。 对于 MySQL，以下脚本可以定义这样的序列：

```java
KeyGeneratingServer1:
auto-increment-increment = 2
auto-increment-offset = 1
    
KeyGeneratingServer2:
auto-increment-increment = 2
auto-increment-offset = 2
```

在两个数据库的前置一个负载均衡器来轮询并处理宕机。这两个服务器可能不同步，其中一个生成的key比另一个多，但这不会在系统中造成任何问题。 可以通过定义单独的 ID 表来扩展这个设计，用于系统中存在的用户、照片评论或其他对象。

或者，可以实现类似于在[**设计类似TinyURL的短链服务**](ch1.md)中讨论过的key生成的方案。

**如何规划系统未来的容量？**

 可以有大量的逻辑分区以适应未来的数据增长，例如在开始时，多个逻辑分区驻留在单个物理数据库服务器上。 由于每个数据库服务器可以有多个数据库实例，可以为任何服务器上的每个逻辑分区拥有单独的数据库。 所以每当某台数据库服务器的数据过多，可以从中迁移一些逻辑分区到另一台服务器。 可以维护一个配置文件（或一个单独的数据库）来映射我们的逻辑分区到数据库服务器； 这将使我们能够轻松地移动分区。 每当想要移动分区，只需要更新配置文件，发布即可。

