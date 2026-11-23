<script setup lang="ts">
useSeoMeta({
  title: 'Giới Thiệu & Chính Sách | Trung Thành Auto',
  description: 'Xưởng may đo thảm lót sàn ô tô Trung Thành Auto tại Hà Nội — Bảo hành 24 tháng, đổi trả 1-1, lắp đặt tại nhà.'
});
</script>

<template>
  <main id="main-content" class="container-app py-5 md:py-8 space-y-6">
    <nav aria-label="Breadcrumb" class="breadcrumb hidden lg:flex">
      <NuxtLink to="/">Trang chủ</NuxtLink>
      <span>&gt;</span>
      <span class="font-semibold text-[#0D2C54]">Giới thiệu</span>
    </nav>

    <section class="card-surface overflow-hidden grid grid-cols-1 lg:grid-cols-2">
      <div class="p-6 sm:p-8 space-y-4 flex flex-col justify-center">
        <span class="text-xs font-bold uppercase tracking-wider text-[#C81E2B]">VỀ TRUNG THÀNH AUTO</span>
        <h1 class="text-xl sm:text-2xl font-bold text-[#0D2C54] m-0 leading-tight">
          Xưởng Sản Xuất &amp; Lắp Đặt Thảm Lót Sàn Ô Tô Chuẩn Phom 3D
        </h1>
        <p class="text-xs sm:text-sm text-slate-600 m-0 leading-relaxed">
          Với hơn 500+ phom sàn chuẩn xác cho các dòng xe tại Việt Nam, Trung Thành Auto chuyên cung cấp thảm da 6D, 360 độ full sàn và nhựa TPE đúc khuôn nguyên sinh không mùi.
        </p>
        <div class="grid grid-cols-3 gap-3 pt-2">
          <div class="bg-[#F4F6F9] rounded-xl p-3 text-center">
            <span class="text-xl font-bold text-[#0D2C54] block tabular-nums">10.000+</span>
            <span class="text-[11px] text-slate-500">Xe đã lắp</span>
          </div>
          <div class="bg-[#F4F6F9] rounded-xl p-3 text-center">
            <span class="text-xl font-bold text-[#0D2C54] block tabular-nums">500+</span>
            <span class="text-[11px] text-slate-500">Phom đời xe</span>
          </div>
          <div class="bg-[#F4F6F9] rounded-xl p-3 text-center">
            <span class="text-xl font-bold text-[#0D2C54] block tabular-nums">24 Tháng</span>
            <span class="text-[11px] text-slate-500">Bảo hành</span>
          </div>
        </div>
      </div>
      <div class="aspect-[16/10] lg:aspect-auto bg-slate-100">
        <img src="/assets/images/about-workshop.webp" alt="Xưởng may đo thảm lót sàn Trung Thành Auto" width="800" height="500" class="w-full h-full object-cover">
      </div>
    </section>

    <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
      <section id="bao-hanh" class="card-surface p-5 space-y-2">
        <h2 class="text-sm font-bold uppercase text-[#0D2C54] m-0">Chính sách bảo hành 24 tháng</h2>
        <p class="text-xs sm:text-sm text-slate-600 m-0 leading-relaxed">
          Bảo hành 24 tháng cho đường chỉ may, bề mặt da PU/Carbon không nổ rộp, chốt khóa định vị và phom sàn. Hỗ trợ kiểm tra bảo hành nhanh theo SĐT đặt hàng.
        </p>
      </section>
      <section id="doi-tra" class="card-surface p-5 space-y-2">
        <h2 class="text-sm font-bold uppercase text-[#0D2C54] m-0">Chính sách đổi trả 1-1</h2>
        <p class="text-xs sm:text-sm text-slate-600 m-0 leading-relaxed">
          Cam kết vừa vặn 100% theo đúng đời xe. Nếu thảm không khớp phom, sai màu hoặc có lỗi từ nhà sản xuất, Trung Thành Auto đổi mới 1-1 miễn phí hoàn toàn.
        </p>
      </section>
      <section id="van-chuyen" class="card-surface p-5 space-y-2">
        <h2 class="text-sm font-bold uppercase text-[#0D2C54] m-0">Giao hàng &amp; Lắp đặt tại nhà</h2>
        <p class="text-xs sm:text-sm text-slate-600 m-0 leading-relaxed">
          Miễn phí giao và lắp đặt tận nơi trong ngày tại nội thành Hà Nội. Giao hàng toàn quốc miễn phí (2–4 ngày), khách được mở kiểm tra và lắp thử trước khi thanh toán.
        </p>
      </section>
      <section id="bao-mat" class="card-surface p-5 space-y-2">
        <h2 class="text-sm font-bold uppercase text-[#0D2C54] m-0">Bảo mật thông tin khách hàng</h2>
        <p class="text-xs sm:text-sm text-slate-600 m-0 leading-relaxed">
          Thông tin họ tên, số điện thoại và địa chỉ chỉ được sử dụng cho mục đích xác nhận phom xe, giao lắp và tra cứu bảo hành 24 tháng, cam kết không chia sẻ cho bên thứ ba.
        </p>
      </section>
    </div>
  </main>
</template>
