export interface NewsArticle {
  id: number;
  slug: string;
  title: string;
  category: 'kinh-nghiem' | 'xu-huong' | 'su-kien';
  categoryLabel: string;
  date: string;
  desc: string;
  image: string;
  featured?: boolean;
  content: string[];
}

export const NEWS_ARTICLES: NewsArticle[] = [
  {
    id: 1,
    slug: 'bi-quyet-chon-tham-lot-san-o-to-phu-hop-cho-mua-mua-gio-bao-bung',
    title: 'Bí quyết chọn thảm lót sàn ô tô phù hợp cho mùa mưa gió bão bùng',
    category: 'kinh-nghiem',
    categoryLabel: 'KINH NGHIỆM',
    date: '15/06/2026',
    desc: 'So sánh ưu nhược điểm giữa thảm nhựa TPE chống nước tuyệt đối và thảm da 6D có lớp rối giữ bùn đất cho mùa mưa.',
    image: '/assets/images/news-featured.webp',
    featured: true,
    content: [
      'Mùa mưa kéo dài là nỗi ám ảnh với sàn nỉ nguyên bản trên ô tô. Chỉ cần vài lần bước lên xe khi giày dép dính nước mưa và bùn đất, sàn nỉ sẽ ẩm mốc và phát sinh mùi hôi rất khó xử lý.',
      'Thảm nhựa TPE đúc khuôn 3D tràn viền có thành cao 3–4cm giúp giữ trọn nước mưa, dễ dàng tháo ra xịt rửa và khô ngay trong vài phút. Đây là lựa chọn hàng đầu cho xe gia đình hay đi tỉnh hoặc thường xuyên di chuyển dưới trời mưa.',
      'Nếu bạn ưu tiên cảm giác êm chân, sang trọng và cách âm gầm tốt hơn, thảm da 6D kèm lớp thảm rối chống bẩn phía trên cũng là phương án rất hiệu quả: lớp rối giữ lại cát bụi và nước, chỉ cần nhấc lớp rối ra giũ sạch sau mỗi chuyến đi.'
    ]
  },
  {
    id: 2,
    slug: 'tai-sao-tham-lot-san-nhua-tpe-lai-tro-thanh-xu-huong-nam-2026',
    title: 'Tại sao thảm lót sàn nhựa TPE lại trở thành xu hướng năm 2026?',
    category: 'xu-huong',
    categoryLabel: 'XU HƯỚNG',
    date: '10/06/2026',
    desc: 'Lý giải sức hút từ vật liệu nhựa TPE nguyên sinh đúc khuôn tràn viền: bền bỉ, không mùi, chống nước tuyệt đối.',
    image: '/assets/images/news-featured.webp',
    content: [
      'Nhựa TPE (Thermoplastic Elastomer) nguyên sinh đạt tiêu chuẩn an toàn sức khỏe, hoàn toàn không phát sinh mùi nhựa hắc ngay cả khi xe đậu ngoài nắng 40°C.',
      'Công nghệ quét Laser 3D giúp từng tấm thảm ôm sát sàn xe từng milimet, có chốt khóa cố định chống xô lệch, đảm bảo an toàn tuyệt đối cho chân ga và chân phanh.',
      'Độ bền thực tế của thảm TPE từ 5–10 năm, không bong tróc, không rách mép và giữ khoang nội thất luôn gọn gàng như xe mới.'
    ]
  },
  {
    id: 3,
    slug: 'su-khac-biet-vuot-troi-giua-tham-da-carbon-va-tham-da-6d-truyen-thong',
    title: 'Sự khác biệt vượt trội giữa thảm da carbon và thảm da 6D truyền thống',
    category: 'kinh-nghiem',
    categoryLabel: 'KINH NGHIỆM',
    date: '08/06/2026',
    desc: 'So sánh chi tiết về tính thẩm mỹ, độ bền chỉ may và khả năng chống bám bụi của hai dòng thảm da bán chạy nhất.',
    image: '/assets/images/news-featured.webp',
    content: [
      'Thảm da 6D truyền thống nổi bật với họa tiết quả trám sang trọng, độ êm ái cao và có thêm lớp rối tháo rời tiện lợi.',
      'Thảm da Carbon và dòng 360 phủ kín toàn bộ thành vách sàn nỉ mang lại vẻ thể thao, chống trầy xước gót giày tốt hơn và rất dễ lau sạch bằng khăn ẩm.',
      'Tùy theo phong cách nội thất xe và nhu cầu sử dụng hằng ngày, kỹ thuật viên Trung Thành Auto sẽ tư vấn phom và màu chỉ tiệp màu ghế da nhất.'
    ]
  },
  {
    id: 4,
    slug: 'trung-thanh-auto-khai-truong-showroom-trung-bay-va-dich-vu-lap-dat-moi-tai-quan-7',
    title: 'Trung Thành Auto khai trương showroom trưng bày và dịch vụ lắp đặt mới tại Quận 7',
    category: 'su-kien',
    categoryLabel: 'SỰ KIỆN',
    date: '01/06/2026',
    desc: 'Không gian showroom mới rộng rãi với đầy đủ bộ phom mẫu thảm thực tế giúp khách hàng trải nghiệm trực quan.',
    image: '/assets/images/about-workshop.webp',
    content: [
      'Showroom trưng bày đầy đủ các dòng thảm 5D, 6D, 360 độ và nhựa TPE nguyên sinh với hơn 50 bộ phom mẫu có sẵn cho các dòng xe phổ biến tại Việt Nam.',
      'Khách hàng có thể trực tiếp sờ thử chất liệu, so sánh màu chỉ với nội thất xe và được kỹ thuật viên lắp đặt hoàn thiện trong 20–30 phút.'
    ]
  },
  {
    id: 5,
    slug: 'huong-dan-tu-ve-sinh-tham-da-5d-tai-nha-cuc-nhanh-trong-10-phut',
    title: 'Hướng dẫn tự vệ sinh thảm da 5D tại nhà cực nhanh trong 10 phút',
    category: 'kinh-nghiem',
    categoryLabel: 'KINH NGHIỆM',
    date: '24/05/2026',
    desc: 'Mẹo sử dụng khăn ẩm vi sợi và dung dịch vệ sinh chuyên dụng giúp làm sạch nhanh bụi đất mà không làm nổ da.',
    image: '/assets/images/news-featured.webp',
    content: [
      'Bước 1: Tháo lớp thảm rối phía trên (nếu có) và giũ sạch bụi đất hoặc xịt rửa trực tiếp bằng nước.',
      'Bước 2: Dùng máy hút bụi cầm tay hút sạch cát mịn trên bề mặt da 5D/6D.',
      'Bước 3: Lau nhẹ bằng khăn microfiber ẩm pha dung dịch vệ sinh nội thất trung tính, sau đó lau khô lại — không ngâm toàn bộ thảm da trong nước.'
    ]
  },
  {
    id: 6,
    slug: 'danh-gia-cua-cac-chuyen-gia-o-to-ve-chat-luong-tham-duc-khuon-tpe-trung-thanh-auto',
    title: 'Đánh giá của các chuyên gia ô tô về chất lượng thảm đúc khuôn TPE Trung Thành Auto',
    category: 'xu-huong',
    categoryLabel: 'XU HƯỚNG',
    date: '15/05/2026',
    desc: 'Đánh giá cao độ ôm khít chân phanh, mép thành thảm dựng đứng giữ nước, bảo vệ sàn nỉ nguyên bản.',
    image: '/assets/images/news-featured.webp',
    content: [
      'Qua quá trình lắp thử nghiệm trên Toyota Fortuner, Mazda CX-5, Honda CR-V và Hyundai SantaFe, bộ thảm TPE Trung Thành Auto đạt độ khít cao tại các góc cua và chốt khóa sàn zin.',
      'Bề mặt vân chống trượt giúp giày dép bám chắc ngay cả khi ướt, đảm bảo an toàn khi thao tác phanh gấp.'
    ]
  },
  {
    id: 7,
    slug: 'cach-bao-quan-tham-lot-san-da-luon-ben-dep-sang-bong-nhu-ngay-dau',
    title: 'Cách bảo quản thảm lót sàn da luôn bền đẹp sáng bóng như ngày đầu',
    category: 'kinh-nghiem',
    categoryLabel: 'KINH NGHIỆM',
    date: '05/05/2026',
    desc: 'Tránh phơi thảm trực tiếp dưới nắng gắt và hạn chế ngâm nước toàn bộ đối với thảm da có lớp đệm mút.',
    image: '/assets/images/news-featured.webp',
    content: [
      'Sau khi vệ sinh, nên phơi thảm da ở nơi râm mát có gió thay vì phơi trực tiếp dưới nắng gắt để giữ bề mặt da PU luôn mềm mại.',
      'Định kỳ 2–3 tháng có thể dưỡng nhẹ bề mặt bằng dung dịch dưỡng da nội thất ô tô để thảm luôn bóng đẹp và bền màu.'
    ]
  }
];
